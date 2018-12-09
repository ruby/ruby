/**********************************************************************

  mjit.c - MRI method JIT compiler functions for Ruby's main thread

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.

**********************************************************************/

/* Functions in this file are never executed on MJIT worker thread.
   So you can safely use Ruby methods and GC in this file. */

/* To share variables privately, include mjit_worker.c instead of linking. */

#include "internal.h"

#if USE_MJIT

#include "mjit_worker.c"

#include "constant.h"
#include "id_table.h"

/* Copy ISeq's states so that race condition does not happen on compilation. */
static void
mjit_copy_job_handler(void *data)
{
    mjit_copy_job_t *job = data;
    const struct rb_iseq_constant_body *body;
    if (stop_worker_p) { /* check if mutex is still alive, before calling CRITICAL_SECTION_START. */
        return;
    }

    CRITICAL_SECTION_START(3, "in mjit_copy_job_handler");
    /* Make sure that this job is never executed when:
       1. job is being modified
       2. alloca memory inside job is expired
       3. ISeq is GC-ed */
    if (job->finish_p || job->unit->iseq == NULL) {
        CRITICAL_SECTION_FINISH(3, "in mjit_copy_job_handler");
        return;
    }

    body = job->unit->iseq->body;
    if (job->cc_entries) {
        memcpy(job->cc_entries, body->cc_entries, sizeof(struct rb_call_cache) * (body->ci_size + body->ci_kw_size));
    }
    if (job->is_entries) {
        memcpy(job->is_entries, body->is_entries, sizeof(union iseq_inline_storage_entry) * body->is_size);
    }

    job->finish_p = TRUE;
    rb_native_cond_broadcast(&mjit_worker_wakeup);
    CRITICAL_SECTION_FINISH(3, "in mjit_copy_job_handler");
}

extern int rb_thread_create_mjit_thread(void (*worker_func)(void));

/* Return an unique file name in /tmp with PREFIX and SUFFIX and
   number ID.  Use getpid if ID == 0.  The return file name exists
   until the next function call.  */
static char *
get_uniq_filename(unsigned long id, const char *prefix, const char *suffix)
{
    char buff[70], *str = buff;
    int size = sprint_uniq_filename(buff, sizeof(buff), id, prefix, suffix);
    str = 0;
    ++size;
    str = xmalloc(size);
    if (size <= (int)sizeof(buff)) {
        memcpy(str, buff, size);
    }
    else {
        sprint_uniq_filename(str, size, id, prefix, suffix);
    }
    return str;
}

/* Wait until workers don't compile any iseq.  It is called at the
   start of GC.  */
void
mjit_gc_start_hook(void)
{
    if (!mjit_enabled)
        return;
    CRITICAL_SECTION_START(4, "mjit_gc_start_hook");
    while (in_jit) {
        verbose(4, "Waiting wakeup from a worker for GC");
        rb_native_cond_wait(&mjit_client_wakeup, &mjit_engine_mutex);
        verbose(4, "Getting wakeup from a worker for GC");
    }
    in_gc = TRUE;
    CRITICAL_SECTION_FINISH(4, "mjit_gc_start_hook");
}

/* Send a signal to workers to continue iseq compilations.  It is
   called at the end of GC.  */
void
mjit_gc_finish_hook(void)
{
    if (!mjit_enabled)
        return;
    CRITICAL_SECTION_START(4, "mjit_gc_finish_hook");
    in_gc = FALSE;
    verbose(4, "Sending wakeup signal to workers after GC");
    rb_native_cond_broadcast(&mjit_gc_wakeup);
    CRITICAL_SECTION_FINISH(4, "mjit_gc_finish_hook");
}

/* Iseqs can be garbage collected.  This function should call when it
   happens.  It removes iseq from the unit.  */
void
mjit_free_iseq(const rb_iseq_t *iseq)
{
    if (!mjit_enabled)
        return;
    CRITICAL_SECTION_START(4, "mjit_free_iseq");
    if (iseq->body->jit_unit) {
        /* jit_unit is not freed here because it may be referred by multiple
           lists of units. `get_from_list` and `mjit_finish` do the job. */
        iseq->body->jit_unit->iseq = NULL;
    }
    CRITICAL_SECTION_FINISH(4, "mjit_free_iseq");
}

/* Free unit list. This should be called only when worker is finished
   because node of unit_queue and one of active_units may have the same unit
   during proceeding unit. */
static void
free_list(struct rb_mjit_unit_list *list, int close_handle_p)
{
    struct rb_mjit_unit *unit = 0, *next;

    list_for_each_safe(&list->head, unit, next, unode) {
        list_del(&unit->unode);
        if (!close_handle_p) unit->handle = NULL; /* Skip dlclose in free_unit() */
        free_unit(unit);
    }
    list->length = 0;
}

/* MJIT info related to an existing continutaion.  */
struct mjit_cont {
    rb_execution_context_t *ec; /* continuation ec */
    struct mjit_cont *prev, *next; /* used to form lists */
};

/* Double linked list of registered continuations. This is used to detect
   units which are in use in unload_units. */
static struct mjit_cont *first_cont;

/* Register a new continuation with thread TH.  Return MJIT info about
   the continuation.  */
struct mjit_cont *
mjit_cont_new(rb_execution_context_t *ec)
{
    struct mjit_cont *cont;

    cont = ZALLOC(struct mjit_cont);
    cont->ec = ec;

    CRITICAL_SECTION_START(3, "in mjit_cont_new");
    if (first_cont == NULL) {
        cont->next = cont->prev = NULL;
    }
    else {
        cont->prev = NULL;
        cont->next = first_cont;
        first_cont->prev = cont;
    }
    first_cont = cont;
    CRITICAL_SECTION_FINISH(3, "in mjit_cont_new");

    return cont;
}

/* Unregister continuation CONT.  */
void
mjit_cont_free(struct mjit_cont *cont)
{
    CRITICAL_SECTION_START(3, "in mjit_cont_new");
    if (cont == first_cont) {
        first_cont = cont->next;
        if (first_cont != NULL)
            first_cont->prev = NULL;
    }
    else {
        cont->prev->next = cont->next;
        if (cont->next != NULL)
            cont->next->prev = cont->prev;
    }
    CRITICAL_SECTION_FINISH(3, "in mjit_cont_new");

    xfree(cont);
}

/* Finish work with continuation info. */
static void
finish_conts(void)
{
    struct mjit_cont *cont, *next;

    for (cont = first_cont; cont != NULL; cont = next) {
        next = cont->next;
        xfree(cont);
    }
}

/* Create unit for ISEQ. */
static void
create_unit(const rb_iseq_t *iseq)
{
    struct rb_mjit_unit *unit;

    unit = ZALLOC(struct rb_mjit_unit);
    if (unit == NULL)
        return;

    unit->id = current_unit_num++;
    unit->iseq = iseq;
    iseq->body->jit_unit = unit;
}

/* Set up field used_code_p for unit iseqs whose iseq on the stack of ec. */
static void
mark_ec_units(rb_execution_context_t *ec)
{
    const rb_control_frame_t *cfp;

    if (ec->vm_stack == NULL)
        return;
    for (cfp = RUBY_VM_END_CONTROL_FRAME(ec) - 1; ; cfp = RUBY_VM_NEXT_CONTROL_FRAME(cfp)) {
        const rb_iseq_t *iseq;
        if (cfp->pc && (iseq = cfp->iseq) != NULL
            && imemo_type((VALUE) iseq) == imemo_iseq
            && (iseq->body->jit_unit) != NULL) {
            iseq->body->jit_unit->used_code_p = TRUE;
        }

        if (cfp == ec->cfp)
            break; /* reached the most recent cfp */
    }
}

/* Unload JIT code of some units to satisfy the maximum permitted
   number of units with a loaded code.  */
static void
unload_units(void)
{
    rb_vm_t *vm = GET_THREAD()->vm;
    rb_thread_t *th = NULL;
    struct rb_mjit_unit *unit = 0, *next, *worst;
    struct mjit_cont *cont;
    int delete_num, units_num = active_units.length;

    /* For now, we don't unload units when ISeq is GCed. We should
       unload such ISeqs first here. */
    list_for_each_safe(&active_units.head, unit, next, unode) {
        if (unit->iseq == NULL) { /* ISeq is GCed. */
            remove_from_list(unit, &active_units);
            free_unit(unit);
        }
    }

    /* Detect units which are in use and can't be unloaded. */
    list_for_each(&active_units.head, unit, unode) {
        assert(unit->iseq != NULL && unit->handle != NULL);
        unit->used_code_p = FALSE;
    }
    list_for_each(&vm->living_threads, th, vmlt_node) {
        mark_ec_units(th->ec);
    }
    for (cont = first_cont; cont != NULL; cont = cont->next) {
        mark_ec_units(cont->ec);
    }

    /* Remove 1/10 units more to decrease unloading calls.  */
    /* TODO: Calculate max total_calls in unit_queue and don't unload units
       whose total_calls are larger than the max. */
    delete_num = active_units.length / 10;
    for (; active_units.length > mjit_opts.max_cache_size - delete_num;) {
        /* Find one unit that has the minimum total_calls. */
        worst = NULL;
        list_for_each(&active_units.head, unit, unode) {
            if (unit->used_code_p) /* We can't unload code on stack. */
                continue;

            if (worst == NULL || worst->iseq->body->total_calls > unit->iseq->body->total_calls) {
                worst = unit;
            }
        }
        if (worst == NULL)
            break;

        /* Unload the worst node. */
        verbose(2, "Unloading unit %d (calls=%lu)", worst->id, worst->iseq->body->total_calls);
        assert(worst->handle != NULL);
        remove_from_list(worst, &active_units);
        free_unit(worst);
    }
    verbose(1, "Too many JIT code -- %d units unloaded", units_num - active_units.length);
}

/* Add ISEQ to be JITed in parallel with the current thread.
   Unload some JIT codes if there are too many of them.  */
void
mjit_add_iseq_to_process(const rb_iseq_t *iseq)
{
    if (!mjit_enabled || pch_status == PCH_FAILED)
        return;

    iseq->body->jit_func = (mjit_func_t)NOT_READY_JIT_ISEQ_FUNC;
    create_unit(iseq);
    if (iseq->body->jit_unit == NULL)
        /* Failure in creating the unit.  */
        return;

    CRITICAL_SECTION_START(3, "in add_iseq_to_process");
    add_to_list(iseq->body->jit_unit, &unit_queue);
    if (active_units.length >= mjit_opts.max_cache_size) {
        unload_units();
    }
    verbose(3, "Sending wakeup signal to workers in mjit_add_iseq_to_process");
    rb_native_cond_broadcast(&mjit_worker_wakeup);
    CRITICAL_SECTION_FINISH(3, "in add_iseq_to_process");
}

/* For this timeout seconds, --jit-wait will wait for JIT compilation finish. */
#define MJIT_WAIT_TIMEOUT_SECONDS 60

/* Wait for JIT compilation finish for --jit-wait, and call the function pointer
   if the compiled result is not NOT_COMPILED_JIT_ISEQ_FUNC. */
VALUE
mjit_wait_call(rb_execution_context_t *ec, struct rb_iseq_constant_body *body)
{
    struct timeval tv;
    int tries = 0;
    tv.tv_sec = 0;
    tv.tv_usec = 1000;
    while (body->jit_func == (mjit_func_t)NOT_READY_JIT_ISEQ_FUNC) {
        tries++;
        if (tries / 1000 > MJIT_WAIT_TIMEOUT_SECONDS || pch_status == PCH_FAILED) {
            CRITICAL_SECTION_START(3, "in mjit_wait_call to set jit_func");
            body->jit_func = (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC; /* JIT worker seems dead. Give up. */
            CRITICAL_SECTION_FINISH(3, "in mjit_wait_call to set jit_func");
            mjit_warning("timed out to wait for JIT finish");
            break;
        }

        CRITICAL_SECTION_START(3, "in mjit_wait_call for a client wakeup");
        rb_native_cond_broadcast(&mjit_worker_wakeup);
        CRITICAL_SECTION_FINISH(3, "in mjit_wait_call for a client wakeup");
        rb_thread_wait_for(tv);
    }

    if ((uintptr_t)body->jit_func <= (uintptr_t)LAST_JIT_ISEQ_FUNC) {
        return Qundef;
    }
    return body->jit_func(ec, ec->cfp);
}

extern VALUE ruby_archlibdir_path, ruby_prefix_path;

/* Initialize header_file, pch_file, libruby_pathflag. Return TRUE on success. */
static int
init_header_filename(void)
{
    int fd;
#ifdef LOAD_RELATIVE
    /* Root path of the running ruby process. Equal to RbConfig::TOPDIR.  */
    VALUE basedir_val;
#endif
    const char *basedir = NULL;
    size_t baselen = 0;
    char *p;
#ifdef _WIN32
    static const char libpathflag[] =
# ifdef _MSC_VER
        "-LIBPATH:"
# else
        "-L"
# endif
        ;
    const size_t libpathflag_len = sizeof(libpathflag) - 1;
#endif

#ifdef LOAD_RELATIVE
    basedir_val = ruby_prefix_path;
    basedir = StringValuePtr(basedir_val);
    baselen = RSTRING_LEN(basedir_val);
#else
    if (getenv("MJIT_SEARCH_BUILD_DIR")) {
        /* This path is not intended to be used on production, but using build directory's
           header file here because people want to run `make test-all` without running
           `make install`. Don't use $MJIT_SEARCH_BUILD_DIR except for test-all. */

        struct stat st;
        const char *hdr = dlsym(RTLD_DEFAULT, "MJIT_HEADER");
        if (!hdr) {
            verbose(1, "No MJIT_HEADER");
        }
        else if (hdr[0] != '/') {
            verbose(1, "Non-absolute header file path: %s", hdr);
        }
        else if (stat(hdr, &st) || !S_ISREG(st.st_mode)) {
            verbose(1, "Non-file header file path: %s", hdr);
        }
        else if ((st.st_uid != getuid()) || (st.st_mode & 022) ||
                 !rb_path_check(hdr)) {
            verbose(1, "Unsafe header file: uid=%ld mode=%#o %s",
                    (long)st.st_uid, (unsigned)st.st_mode, hdr);
            return FALSE;
        }
        else {
            /* Do not pass PRELOADENV to child processes, on
             * multi-arch environment */
            verbose(3, "PRELOADENV("PRELOADENV")=%s", getenv(PRELOADENV));
            /* assume no other PRELOADENV in test-all */
            unsetenv(PRELOADENV);
            verbose(3, "MJIT_HEADER: %s", hdr);
            header_file = ruby_strdup(hdr);
            if (!header_file) return FALSE;
        }
    }
    else
#endif
#ifndef _MSC_VER
    {
        /* A name of the header file included in any C file generated by MJIT for iseqs. */
        static const char header_name[] = MJIT_HEADER_INSTALL_DIR "/" MJIT_MIN_HEADER_NAME;
        const size_t header_name_len = sizeof(header_name) - 1;

        header_file = xmalloc(baselen + header_name_len + 1);
        p = append_str2(header_file, basedir, baselen);
        p = append_str2(p, header_name, header_name_len + 1);

        if ((fd = rb_cloexec_open(header_file, O_RDONLY, 0)) < 0) {
            verbose(1, "Cannot access header file: %s", header_file);
            xfree(header_file);
            header_file = NULL;
            return FALSE;
        }
        (void)close(fd);
    }

    pch_file = get_uniq_filename(0, MJIT_TMP_PREFIX "h", ".h.gch");
#else
    {
        static const char pch_name[] = MJIT_HEADER_INSTALL_DIR "/" MJIT_PRECOMPILED_HEADER_NAME;
        const size_t pch_name_len = sizeof(pch_name) - 1;

        pch_file = xmalloc(baselen + pch_name_len + 1);
        p = append_str2(pch_file, basedir, baselen);
        p = append_str2(p, pch_name, pch_name_len + 1);
        if ((fd = rb_cloexec_open(pch_file, O_RDONLY, 0)) < 0) {
            verbose(1, "Cannot access precompiled header file: %s", pch_file);
            xfree(pch_file);
            pch_file = NULL;
            return FALSE;
        }
        (void)close(fd);
    }
#endif

#ifdef _WIN32
    basedir_val = ruby_archlibdir_path;
    basedir = StringValuePtr(basedir_val);
    baselen = RSTRING_LEN(basedir_val);
    libruby_pathflag = p = xmalloc(libpathflag_len + baselen + 1);
    p = append_str(p, libpathflag);
    p = append_str2(p, basedir, baselen);
    *p = '\0';
#endif

    return TRUE;
}

static enum rb_id_table_iterator_result
valid_class_serials_add_i(ID key, VALUE v, void *unused)
{
    rb_const_entry_t *ce = (rb_const_entry_t *)v;
    VALUE value = ce->value;

    if (!rb_is_const_id(key)) return ID_TABLE_CONTINUE;
    if (RB_TYPE_P(value, T_MODULE) || RB_TYPE_P(value, T_CLASS)) {
        mjit_add_class_serial(RCLASS_SERIAL(value));
    }
    return ID_TABLE_CONTINUE;
}

#ifdef _WIN32
UINT rb_w32_system_tmpdir(WCHAR *path, UINT len);
#endif

static char *
system_default_tmpdir(void)
{
    /* c.f. ext/etc/etc.c:etc_systmpdir() */
#ifdef _WIN32
    WCHAR tmppath[_MAX_PATH];
    UINT len = rb_w32_system_tmpdir(tmppath, numberof(tmppath));
    if (len) {
        int blen = WideCharToMultiByte(CP_UTF8, 0, tmppath, len, NULL, 0, NULL, NULL);
        char *tmpdir = xmalloc(blen + 1);
        WideCharToMultiByte(CP_UTF8, 0, tmppath, len, tmpdir, blen, NULL, NULL);
        tmpdir[blen] = '\0';
        return tmpdir;
    }
#elif defined _CS_DARWIN_USER_TEMP_DIR
    char path[MAXPATHLEN];
    size_t len = confstr(_CS_DARWIN_USER_TEMP_DIR, path, sizeof(path));
    if (len > 0) {
        char *tmpdir = xmalloc(len);
        if (len > sizeof(path)) {
            confstr(_CS_DARWIN_USER_TEMP_DIR, tmpdir, len);
        }
        else {
            memcpy(tmpdir, path, len);
        }
        return tmpdir;
    }
#endif
    return 0;
}

static int
check_tmpdir(const char *dir)
{
    struct stat st;

    if (!dir) return FALSE;
    if (stat(dir, &st)) return FALSE;
#ifndef S_ISDIR
#   define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#endif
    if (!S_ISDIR(st.st_mode)) return FALSE;
#ifndef _WIN32
# ifndef S_IWOTH
#   define S_IWOTH 002
# endif
    if (st.st_mode & S_IWOTH) {
# ifdef S_ISVTX
        if (!(st.st_mode & S_ISVTX)) return FALSE;
# else
        return FALSE;
# endif
    }
    if (access(dir, W_OK)) return FALSE;
#endif
    return TRUE;
}

static char *
system_tmpdir(void)
{
    char *tmpdir;
# define RETURN_ENV(name) \
    if (check_tmpdir(tmpdir = getenv(name))) return ruby_strdup(tmpdir)
    RETURN_ENV("TMPDIR");
    RETURN_ENV("TMP");
    tmpdir = system_default_tmpdir();
    if (check_tmpdir(tmpdir)) return tmpdir;
    return ruby_strdup("/tmp");
# undef RETURN_ENV
}

/* Default permitted number of units with a JIT code kept in
   memory.  */
#define DEFAULT_CACHE_SIZE 1000
/* A default threshold used to add iseq to JIT. */
#define DEFAULT_MIN_CALLS_TO_ADD 5
/* Minimum value for JIT cache size.  */
#define MIN_CACHE_SIZE 10

/* Start MJIT worker. Return TRUE if worker is sucessfully started. */
static int
start_worker(void)
{
    stop_worker_p = FALSE;
    worker_stopped = FALSE;

    if (!rb_thread_create_mjit_thread(mjit_worker)) {
        mjit_enabled = FALSE;
        rb_native_mutex_destroy(&mjit_engine_mutex);
        rb_native_cond_destroy(&mjit_pch_wakeup);
        rb_native_cond_destroy(&mjit_client_wakeup);
        rb_native_cond_destroy(&mjit_worker_wakeup);
        rb_native_cond_destroy(&mjit_gc_wakeup);
        verbose(1, "Failure in MJIT thread initialization\n");
        return FALSE;
    }
    return TRUE;
}

/* Initialize MJIT.  Start a thread creating the precompiled header and
   processing ISeqs.  The function should be called first for using MJIT.
   If everything is successfull, MJIT_INIT_P will be TRUE.  */
void
mjit_init(struct mjit_options *opts)
{
    mjit_opts = *opts;
    mjit_enabled = TRUE;
    mjit_call_p = TRUE;

    /* Normalize options */
    if (mjit_opts.min_calls == 0)
        mjit_opts.min_calls = DEFAULT_MIN_CALLS_TO_ADD;
    if (mjit_opts.max_cache_size <= 0)
        mjit_opts.max_cache_size = DEFAULT_CACHE_SIZE;
    if (mjit_opts.max_cache_size < MIN_CACHE_SIZE)
        mjit_opts.max_cache_size = MIN_CACHE_SIZE;

    /* Initialize variables for compilation */
#ifdef _MSC_VER
    pch_status = PCH_SUCCESS; /* has prebuilt precompiled header */
#else
    pch_status = PCH_NOT_READY;
#endif
    cc_path = CC_COMMON_ARGS[0];
    verbose(2, "MJIT: CC defaults to %s", cc_path);
    cc_common_args = xmalloc(sizeof(CC_COMMON_ARGS));
    memcpy((void *)cc_common_args, CC_COMMON_ARGS, sizeof(CC_COMMON_ARGS));
#if MJIT_CFLAGS_PIPE
    { /* eliminate a flag incompatible with `-pipe` */
        size_t i, j;
        for (i = 0, j = 0; i < sizeof(CC_COMMON_ARGS) / sizeof(char *); i++) {
            if (CC_COMMON_ARGS[i] && strncmp("-save-temps", CC_COMMON_ARGS[i], strlen("-save-temps")) == 0)
                continue; /* skip -save-temps flag */
            cc_common_args[j] = CC_COMMON_ARGS[i];
            j++;
        }
    }
#endif

    tmp_dir = system_tmpdir();
    verbose(2, "MJIT: tmp_dir is %s", tmp_dir);

    if (!init_header_filename()) {
        mjit_enabled = FALSE;
        verbose(1, "Failure in MJIT header file name initialization\n");
        return;
    }
    pch_owner_pid = getpid();

    /* Initialize mutex */
    rb_native_mutex_initialize(&mjit_engine_mutex);
    rb_native_cond_initialize(&mjit_pch_wakeup);
    rb_native_cond_initialize(&mjit_client_wakeup);
    rb_native_cond_initialize(&mjit_worker_wakeup);
    rb_native_cond_initialize(&mjit_gc_wakeup);

    /* Initialize class_serials cache for compilation */
    valid_class_serials = rb_hash_new();
    rb_obj_hide(valid_class_serials);
    rb_gc_register_mark_object(valid_class_serials);
    mjit_add_class_serial(RCLASS_SERIAL(rb_cObject));
    mjit_add_class_serial(RCLASS_SERIAL(CLASS_OF(rb_vm_top_self())));
    if (RCLASS_CONST_TBL(rb_cObject)) {
        rb_id_table_foreach(RCLASS_CONST_TBL(rb_cObject), valid_class_serials_add_i, NULL);
    }

    /* Initialize worker thread */
    start_worker();
}

static void
stop_worker(void)
{
    rb_execution_context_t *ec = GET_EC();

    while (!worker_stopped) {
        verbose(3, "Sending cancel signal to worker");
        CRITICAL_SECTION_START(3, "in stop_worker");
        stop_worker_p = TRUE; /* Setting this inside loop because RUBY_VM_CHECK_INTS may make this FALSE. */
        rb_native_cond_broadcast(&mjit_worker_wakeup);
        CRITICAL_SECTION_FINISH(3, "in stop_worker");
        RUBY_VM_CHECK_INTS(ec);
    }
}

/* Stop JIT-compiling methods but compiled code is kept available. */
VALUE
mjit_pause(int wait_p)
{
    if (!mjit_enabled) {
        rb_raise(rb_eRuntimeError, "MJIT is not enabled");
    }
    if (worker_stopped) {
        return Qfalse;
    }

    /* Flush all queued units with no option or `wait: true` */
    if (wait_p) {
        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 1000;

        while (unit_queue.length > 0 && active_units.length < mjit_opts.max_cache_size) { /* inverse of condition that waits for mjit_worker_wakeup */
            CRITICAL_SECTION_START(3, "in mjit_pause for a worker wakeup");
            rb_native_cond_broadcast(&mjit_worker_wakeup);
            CRITICAL_SECTION_FINISH(3, "in mjit_pause for a worker wakeup");
            rb_thread_wait_for(tv);
        }
    }

    stop_worker();
    return Qtrue;
}

/* Restart JIT-compiling methods after mjit_pause. */
VALUE
mjit_resume(void)
{
    if (!mjit_enabled) {
        rb_raise(rb_eRuntimeError, "MJIT is not enabled");
    }
    if (!worker_stopped) {
        return Qfalse;
    }

    if (!start_worker()) {
        rb_raise(rb_eRuntimeError, "Failed to resume MJIT worker");
    }
    return Qtrue;
}

/* Skip calling `clean_object_files` for units which currently exist in the list. */
static void
skip_cleaning_object_files(struct rb_mjit_unit_list *list)
{
    struct rb_mjit_unit *unit = NULL, *next;

    /* No mutex for list, assuming MJIT worker does not exist yet since it's immediately after fork. */
    list_for_each_safe(&list->head, unit, next, unode) {
#ifndef _MSC_VER /* Actually mswin does not reach here since it doesn't have fork */
        if (unit->o_file) unit->o_file_inherited_p = TRUE;
#endif

#if defined(_WIN32) /* mswin doesn't reach here either. This is for MinGW. */
        if (unit->so_file) unit->so_file = NULL;
#endif
    }
}

/* This is called after fork initiated by Ruby's method to launch MJIT worker thread
   for child Ruby process.

   In multi-process Ruby applications, child Ruby processes do most of the jobs.
   Thus we want child Ruby processes to enqueue ISeqs to MJIT worker's queue and
   call the JIT-ed code.

   But unfortunately current MJIT-generated code is process-specific. After the fork,
   JIT-ed code created by parent Ruby process cannot be used in child Ruby process
   because the code could rely on inline cache values (ivar's IC, send's CC) which
   may vary between processes after fork or embed some process-specific addresses.

   So child Ruby process can't request parent process to JIT an ISeq and use the code.
   Instead of that, MJIT worker thread is created for all child Ruby processes, even
   while child processes would end up with compiling the same ISeqs.
 */
void
mjit_child_after_fork(void)
{
    if (!mjit_enabled)
        return;

    /* Let parent process delete the already-compiled object files.
       This must be done before starting MJIT worker on child process. */
    skip_cleaning_object_files(&active_units);

    /* MJIT worker thread is not inherited on fork. Start it for this child process. */
    start_worker();
}

/* Finish the threads processing units and creating PCH, finalize
   and free MJIT data.  It should be called last during MJIT
   life.

   If close_handle_p is TRUE, it calls dlclose() for JIT-ed code. So it should be FALSE
   if the code can still be on stack. ...But it means to leak JIT-ed handle forever (FIXME). */
void
mjit_finish(int close_handle_p)
{
    if (!mjit_enabled)
        return;

    /* Wait for pch finish */
    verbose(2, "Stopping worker thread");
    CRITICAL_SECTION_START(3, "in mjit_finish to wakeup from pch");
    /* As our threads are detached, we could just cancel them.  But it
       is a bad idea because OS processes (C compiler) started by
       threads can produce temp files.  And even if the temp files are
       removed, the used C compiler still complaint about their
       absence.  So wait for a clean finish of the threads.  */
    while (pch_status == PCH_NOT_READY) {
        verbose(3, "Waiting wakeup from make_pch");
        rb_native_cond_wait(&mjit_pch_wakeup, &mjit_engine_mutex);
    }
    CRITICAL_SECTION_FINISH(3, "in mjit_finish to wakeup from pch");

    /* Stop worker */
    stop_worker();

    rb_native_mutex_destroy(&mjit_engine_mutex);
    rb_native_cond_destroy(&mjit_pch_wakeup);
    rb_native_cond_destroy(&mjit_client_wakeup);
    rb_native_cond_destroy(&mjit_worker_wakeup);
    rb_native_cond_destroy(&mjit_gc_wakeup);

#ifndef _MSC_VER /* mswin has prebuilt precompiled header */
    if (!mjit_opts.save_temps && getpid() == pch_owner_pid)
        remove_file(pch_file);

    xfree(header_file); header_file = NULL;
#endif
    xfree((void *)cc_common_args); cc_common_args = NULL;
    xfree(tmp_dir); tmp_dir = NULL;
    xfree(pch_file); pch_file = NULL;

    mjit_call_p = FALSE;
    free_list(&unit_queue, close_handle_p);
    free_list(&active_units, close_handle_p);
    free_list(&compact_units, close_handle_p);
    finish_conts();

    mjit_enabled = FALSE;
    verbose(1, "Successful MJIT finish");
}

void
mjit_mark(void)
{
    struct rb_mjit_unit *unit = 0;
    if (!mjit_enabled)
        return;
    RUBY_MARK_ENTER("mjit");
    CRITICAL_SECTION_START(4, "mjit_mark");
    list_for_each(&unit_queue.head, unit, unode) {
        if (unit->iseq) { /* ISeq is still not GCed */
            VALUE iseq = (VALUE)unit->iseq;
            CRITICAL_SECTION_FINISH(4, "mjit_mark rb_gc_mark");

            /* Don't wrap critical section with this. This may trigger GC,
               and in that case mjit_gc_start_hook causes deadlock. */
            rb_gc_mark(iseq);

            CRITICAL_SECTION_START(4, "mjit_mark rb_gc_mark");
        }
    }
    CRITICAL_SECTION_FINISH(4, "mjit_mark");
    RUBY_MARK_LEAVE("mjit");
}

/* A hook to update valid_class_serials. */
void
mjit_add_class_serial(rb_serial_t class_serial)
{
    if (!mjit_enabled)
        return;

    /* Do not wrap CRITICAL_SECTION here. This function is only called in main thread
       and guarded by GVL, and `rb_hash_aset` may cause GC and deadlock in it. */
    rb_hash_aset(valid_class_serials, LONG2FIX(class_serial), Qtrue);
}

/* A hook to update valid_class_serials. */
void
mjit_remove_class_serial(rb_serial_t class_serial)
{
    if (!mjit_enabled)
        return;

    CRITICAL_SECTION_START(3, "in mjit_remove_class_serial");
    rb_hash_delete_entry(valid_class_serials, LONG2FIX(class_serial));
    CRITICAL_SECTION_FINISH(3, "in mjit_remove_class_serial");
}

#endif
