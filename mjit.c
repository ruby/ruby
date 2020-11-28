/**********************************************************************

  mjit.c - MRI method JIT compiler functions for Ruby's main thread

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.

**********************************************************************/

// Functions in this file are never executed on MJIT worker thread.
// So you can safely use Ruby methods and GC in this file.

// To share variables privately, include mjit_worker.c instead of linking.

#include "ruby/internal/config.h" // defines USE_MJIT

#if USE_MJIT

#include "constant.h"
#include "id_table.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/cont.h"
#include "internal/file.h"
#include "internal/hash.h"
#include "internal/warnings.h"

#include "mjit_worker.c"

extern int rb_thread_create_mjit_thread(void (*worker_func)(void));

// Return an unique file name in /tmp with PREFIX and SUFFIX and
// number ID.  Use getpid if ID == 0.  The return file name exists
// until the next function call.
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

// Wait until workers don't compile any iseq.  It is called at the
// start of GC.
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
    in_gc++;
    CRITICAL_SECTION_FINISH(4, "mjit_gc_start_hook");
}

// Send a signal to workers to continue iseq compilations.  It is
// called at the end of GC.
void
mjit_gc_exit_hook(void)
{
    if (!mjit_enabled)
        return;
    CRITICAL_SECTION_START(4, "mjit_gc_exit_hook");
    in_gc--;
    RUBY_ASSERT_ALWAYS(in_gc >= 0);
    if (!in_gc) {
        verbose(4, "Sending wakeup signal to workers after GC");
        rb_native_cond_broadcast(&mjit_gc_wakeup);
    }
    CRITICAL_SECTION_FINISH(4, "mjit_gc_exit_hook");
}

// Deal with ISeq movement from compactor
void
mjit_update_references(const rb_iseq_t *iseq)
{
    if (!mjit_enabled)
        return;

    CRITICAL_SECTION_START(4, "mjit_update_references");
    if (iseq->body->jit_unit) {
        iseq->body->jit_unit->iseq = (rb_iseq_t *)rb_gc_location((VALUE)iseq->body->jit_unit->iseq);
        // We need to invalidate JIT-ed code for the ISeq because it embeds pointer addresses.
        // To efficiently do that, we use the same thing as TracePoint and thus everything is cancelled for now.
        // See mjit.h and tool/ruby_vm/views/_mjit_compile_insn.erb for how `mjit_call_p` is used.
        mjit_call_p = false; // TODO: instead of cancelling all, invalidate only this one and recompile it with some threshold.
    }

    // Units in stale_units (list of over-speculated and invalidated code) are not referenced from
    // `iseq->body->jit_unit` anymore (because new one replaces that). So we need to check them too.
    // TODO: we should be able to reduce the number of units checked here.
    struct rb_mjit_unit *unit = NULL;
    list_for_each(&stale_units.head, unit, unode) {
        if (unit->iseq == iseq) {
            unit->iseq = (rb_iseq_t *)rb_gc_location((VALUE)unit->iseq);
        }
    }
    CRITICAL_SECTION_FINISH(4, "mjit_update_references");
}

// Iseqs can be garbage collected.  This function should call when it
// happens.  It removes iseq from the unit.
void
mjit_free_iseq(const rb_iseq_t *iseq)
{
    if (!mjit_enabled)
        return;

    CRITICAL_SECTION_START(4, "mjit_free_iseq");
    if (iseq->body->jit_unit) {
        // jit_unit is not freed here because it may be referred by multiple
        // lists of units. `get_from_list` and `mjit_finish` do the job.
        iseq->body->jit_unit->iseq = NULL;
    }
    // Units in stale_units (list of over-speculated and invalidated code) are not referenced from
    // `iseq->body->jit_unit` anymore (because new one replaces that). So we need to check them too.
    // TODO: we should be able to reduce the number of units checked here.
    struct rb_mjit_unit *unit = NULL;
    list_for_each(&stale_units.head, unit, unode) {
        if (unit->iseq == iseq) {
            unit->iseq = NULL;
        }
    }
    CRITICAL_SECTION_FINISH(4, "mjit_free_iseq");
}

// Free unit list. This should be called only when worker is finished
// because node of unit_queue and one of active_units may have the same unit
// during proceeding unit.
static void
free_list(struct rb_mjit_unit_list *list, bool close_handle_p)
{
    struct rb_mjit_unit *unit = 0, *next;

    list_for_each_safe(&list->head, unit, next, unode) {
        list_del(&unit->unode);
        if (!close_handle_p) unit->handle = NULL; /* Skip dlclose in free_unit() */

        if (list == &stale_units) { // `free_unit(unit)` crashes after GC.compact on `stale_units`
            /*
             * TODO: REVERT THIS BRANCH
             * Debug the crash on stale_units w/ GC.compact and just use `free_unit(unit)`!!
             */
            if (unit->handle && dlclose(unit->handle)) {
                mjit_warning("failed to close handle for u%d: %s", unit->id, dlerror());
            }
            clean_temp_files(unit);
            free(unit);
        }
        else {
            free_unit(unit);
        }
    }
    list->length = 0;
}

// Register a new continuation with execution context `ec`. Return MJIT info about
// the continuation.
struct mjit_cont *
mjit_cont_new(rb_execution_context_t *ec)
{
    struct mjit_cont *cont;

    // We need to use calloc instead of something like ZALLOC to avoid triggering GC here.
    // When this function is called from rb_thread_alloc through rb_threadptr_root_fiber_setup,
    // the thread is still being prepared and marking it causes SEGV.
    cont = calloc(1, sizeof(struct mjit_cont));
    if (cont == NULL)
        rb_memerror();
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

// Unregister continuation `cont`.
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

    free(cont);
}

// Finish work with continuation info.
static void
finish_conts(void)
{
    struct mjit_cont *cont, *next;

    for (cont = first_cont; cont != NULL; cont = next) {
        next = cont->next;
        xfree(cont);
    }
}

// Create unit for `iseq`.
static void
create_unit(const rb_iseq_t *iseq)
{
    struct rb_mjit_unit *unit;

    unit = ZALLOC(struct rb_mjit_unit);
    if (unit == NULL)
        return;

    unit->id = current_unit_num++;
    unit->iseq = (rb_iseq_t *)iseq;
    iseq->body->jit_unit = unit;
}

static void
mjit_add_iseq_to_process(const rb_iseq_t *iseq, const struct rb_mjit_compile_info *compile_info)
{
    if (!mjit_enabled || pch_status == PCH_FAILED)
        return;

    RB_DEBUG_COUNTER_INC(mjit_add_iseq_to_process);
    iseq->body->jit_func = (mjit_func_t)NOT_READY_JIT_ISEQ_FUNC;
    create_unit(iseq);
    if (iseq->body->jit_unit == NULL)
        // Failure in creating the unit.
        return;
    if (compile_info != NULL)
        iseq->body->jit_unit->compile_info = *compile_info;

    CRITICAL_SECTION_START(3, "in add_iseq_to_process");
    add_to_list(iseq->body->jit_unit, &unit_queue);
    if (active_units.length >= mjit_opts.max_cache_size) {
        unload_requests++;
    }
    verbose(3, "Sending wakeup signal to workers in mjit_add_iseq_to_process");
    rb_native_cond_broadcast(&mjit_worker_wakeup);
    CRITICAL_SECTION_FINISH(3, "in add_iseq_to_process");
}

// Add ISEQ to be JITed in parallel with the current thread.
// Unload some JIT codes if there are too many of them.
void
rb_mjit_add_iseq_to_process(const rb_iseq_t *iseq)
{
    mjit_add_iseq_to_process(iseq, NULL);
}

// For this timeout seconds, --jit-wait will wait for JIT compilation finish.
#define MJIT_WAIT_TIMEOUT_SECONDS 60

static void
mjit_wait(struct rb_iseq_constant_body *body)
{
    struct timeval tv;
    int tries = 0;
    tv.tv_sec = 0;
    tv.tv_usec = 1000;
    while (body->jit_func == (mjit_func_t)NOT_READY_JIT_ISEQ_FUNC) {
        tries++;
        if (tries / 1000 > MJIT_WAIT_TIMEOUT_SECONDS || pch_status == PCH_FAILED) {
            CRITICAL_SECTION_START(3, "in rb_mjit_wait_call to set jit_func");
            body->jit_func = (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC; // JIT worker seems dead. Give up.
            CRITICAL_SECTION_FINISH(3, "in rb_mjit_wait_call to set jit_func");
            mjit_warning("timed out to wait for JIT finish");
            break;
        }

        CRITICAL_SECTION_START(3, "in rb_mjit_wait_call for a client wakeup");
        rb_native_cond_broadcast(&mjit_worker_wakeup);
        CRITICAL_SECTION_FINISH(3, "in rb_mjit_wait_call for a client wakeup");
        rb_thread_wait_for(tv);
    }
}

// Wait for JIT compilation finish for --jit-wait, and call the function pointer
// if the compiled result is not NOT_COMPILED_JIT_ISEQ_FUNC.
VALUE
rb_mjit_wait_call(rb_execution_context_t *ec, struct rb_iseq_constant_body *body)
{
    mjit_wait(body);
    if ((uintptr_t)body->jit_func <= (uintptr_t)LAST_JIT_ISEQ_FUNC) {
        return Qundef;
    }
    return body->jit_func(ec, ec->cfp);
}

struct rb_mjit_compile_info*
rb_mjit_iseq_compile_info(const struct rb_iseq_constant_body *body)
{
    assert(body->jit_unit != NULL);
    return &body->jit_unit->compile_info;
}

static void
mjit_recompile(const rb_iseq_t *iseq)
{
    if ((uintptr_t)iseq->body->jit_func <= (uintptr_t)LAST_JIT_ISEQ_FUNC)
        return;

    verbose(1, "JIT recompile: %s@%s:%d", RSTRING_PTR(iseq->body->location.label),
            RSTRING_PTR(rb_iseq_path(iseq)), FIX2INT(iseq->body->location.first_lineno));

    CRITICAL_SECTION_START(3, "in rb_mjit_recompile_iseq");
    remove_from_list(iseq->body->jit_unit, &active_units);
    iseq->body->jit_func = (mjit_func_t)NOT_ADDED_JIT_ISEQ_FUNC;
    add_to_list(iseq->body->jit_unit, &stale_units);
    CRITICAL_SECTION_FINISH(3, "in rb_mjit_recompile_iseq");

    mjit_add_iseq_to_process(iseq, &iseq->body->jit_unit->compile_info);
    if (UNLIKELY(mjit_opts.wait)) {
        mjit_wait(iseq->body);
    }
}

// Recompile iseq, disabling send optimization
void
rb_mjit_recompile_send(const rb_iseq_t *iseq)
{
    rb_mjit_iseq_compile_info(iseq->body)->disable_send_cache = true;
    mjit_recompile(iseq);
}

// Recompile iseq, disabling ivar optimization
void
rb_mjit_recompile_ivar(const rb_iseq_t *iseq)
{
    rb_mjit_iseq_compile_info(iseq->body)->disable_ivar_cache = true;
    mjit_recompile(iseq);
}

// Recompile iseq, disabling exivar optimization
void
rb_mjit_recompile_exivar(const rb_iseq_t *iseq)
{
    rb_mjit_iseq_compile_info(iseq->body)->disable_exivar_cache = true;
    mjit_recompile(iseq);
}

// Recompile iseq, disabling method inlining
void
rb_mjit_recompile_inlining(const rb_iseq_t *iseq)
{
    rb_mjit_iseq_compile_info(iseq->body)->disable_inlining = true;
    mjit_recompile(iseq);
}

extern VALUE ruby_archlibdir_path, ruby_prefix_path;

// Initialize header_file, pch_file, libruby_pathflag. Return true on success.
static bool
init_header_filename(void)
{
    int fd;
#ifdef LOAD_RELATIVE
    // Root path of the running ruby process. Equal to RbConfig::TOPDIR.
    VALUE basedir_val;
#endif
    const char *basedir = "";
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
        // This path is not intended to be used on production, but using build directory's
        // header file here because people want to run `make test-all` without running
        // `make install`. Don't use $MJIT_SEARCH_BUILD_DIR except for test-all.

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
            // Do not pass PRELOADENV to child processes, on
            // multi-arch environment
            verbose(3, "PRELOADENV("PRELOADENV")=%s", getenv(PRELOADENV));
            // assume no other PRELOADENV in test-all
            unsetenv(PRELOADENV);
            verbose(3, "MJIT_HEADER: %s", hdr);
            header_file = ruby_strdup(hdr);
            if (!header_file) return false;
        }
    }
    else
#endif
#ifndef _MSC_VER
    {
        // A name of the header file included in any C file generated by MJIT for iseqs.
        static const char header_name[] = MJIT_HEADER_INSTALL_DIR "/" MJIT_MIN_HEADER_NAME;
        const size_t header_name_len = sizeof(header_name) - 1;

        header_file = xmalloc(baselen + header_name_len + 1);
        p = append_str2(header_file, basedir, baselen);
        p = append_str2(p, header_name, header_name_len + 1);

        if ((fd = rb_cloexec_open(header_file, O_RDONLY, 0)) < 0) {
            verbose(1, "Cannot access header file: %s", header_file);
            xfree(header_file);
            header_file = NULL;
            return false;
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
            return false;
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

    return true;
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
    // c.f. ext/etc/etc.c:etc_systmpdir()
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

// Minimum value for JIT cache size.
#define MIN_CACHE_SIZE 10
// Default permitted number of units with a JIT code kept in memory.
#define DEFAULT_MAX_CACHE_SIZE 100
// A default threshold used to add iseq to JIT.
#define DEFAULT_MIN_CALLS_TO_ADD 10000

// Start MJIT worker. Return TRUE if worker is successfully started.
static bool
start_worker(void)
{
    stop_worker_p = false;
    worker_stopped = false;

    if (!rb_thread_create_mjit_thread(mjit_worker)) {
        mjit_enabled = false;
        rb_native_mutex_destroy(&mjit_engine_mutex);
        rb_native_cond_destroy(&mjit_pch_wakeup);
        rb_native_cond_destroy(&mjit_client_wakeup);
        rb_native_cond_destroy(&mjit_worker_wakeup);
        rb_native_cond_destroy(&mjit_gc_wakeup);
        verbose(1, "Failure in MJIT thread initialization\n");
        return false;
    }
    return true;
}

// There's no strndup on Windows
static char*
ruby_strndup(const char *str, size_t n)
{
    char *ret = xmalloc(n + 1);
    memcpy(ret, str, n);
    ret[n] = '\0';
    return ret;
}

// Convert "foo bar" to {"foo", "bar", NULL} array. Caller is responsible for
// freeing a returned buffer and its elements.
static char **
split_flags(const char *flags)
{
    char *buf[MAXPATHLEN];
    int i = 0;
    char *next;
    for (; flags != NULL; flags = next) {
        next = strchr(flags, ' ');
        if (next == NULL) {
            if (strlen(flags) > 0)
                buf[i++] = strdup(flags);
        }
        else {
            if (next > flags)
                buf[i++] = ruby_strndup(flags, next - flags);
            next++; // skip space
        }
    }

    char **ret = xmalloc(sizeof(char *) * (i + 1));
    memcpy(ret, buf, sizeof(char *) * i);
    ret[i] = NULL;
    return ret;
}

// Initialize MJIT.  Start a thread creating the precompiled header and
// processing ISeqs.  The function should be called first for using MJIT.
// If everything is successful, MJIT_INIT_P will be TRUE.
void
mjit_init(const struct mjit_options *opts)
{
    mjit_opts = *opts;
    mjit_enabled = true;
    mjit_call_p = true;

    // Normalize options
    if (mjit_opts.min_calls == 0)
        mjit_opts.min_calls = DEFAULT_MIN_CALLS_TO_ADD;
    if (mjit_opts.max_cache_size <= 0)
        mjit_opts.max_cache_size = DEFAULT_MAX_CACHE_SIZE;
    if (mjit_opts.max_cache_size < MIN_CACHE_SIZE)
        mjit_opts.max_cache_size = MIN_CACHE_SIZE;

    // Initialize variables for compilation
#ifdef _MSC_VER
    pch_status = PCH_SUCCESS; // has prebuilt precompiled header
#else
    pch_status = PCH_NOT_READY;
#endif
    cc_path = CC_COMMON_ARGS[0];
    verbose(2, "MJIT: CC defaults to %s", cc_path);
    cc_common_args = xmalloc(sizeof(CC_COMMON_ARGS));
    memcpy((void *)cc_common_args, CC_COMMON_ARGS, sizeof(CC_COMMON_ARGS));
    cc_added_args = split_flags(opts->debug_flags);
    xfree(opts->debug_flags);
#if MJIT_CFLAGS_PIPE
    // eliminate a flag incompatible with `-pipe`
    for (size_t i = 0, j = 0; i < sizeof(CC_COMMON_ARGS) / sizeof(char *); i++) {
        if (CC_COMMON_ARGS[i] && strncmp("-save-temps", CC_COMMON_ARGS[i], strlen("-save-temps")) == 0)
            continue; // skip -save-temps flag
        cc_common_args[j] = CC_COMMON_ARGS[i];
        j++;
    }
#endif

    tmp_dir = system_tmpdir();
    verbose(2, "MJIT: tmp_dir is %s", tmp_dir);

    if (!init_header_filename()) {
        mjit_enabled = false;
        verbose(1, "Failure in MJIT header file name initialization\n");
        return;
    }
    pch_owner_pid = getpid();

    // Initialize mutex
    rb_native_mutex_initialize(&mjit_engine_mutex);
    rb_native_cond_initialize(&mjit_pch_wakeup);
    rb_native_cond_initialize(&mjit_client_wakeup);
    rb_native_cond_initialize(&mjit_worker_wakeup);
    rb_native_cond_initialize(&mjit_gc_wakeup);

    // Make sure the saved_ec of the initial thread's root_fiber is scanned by mark_ec_units.
    //
    // rb_threadptr_root_fiber_setup for the initial thread is called before mjit_init,
    // meaning mjit_cont_new is skipped for the root_fiber. Therefore we need to call
    // rb_fiber_init_mjit_cont again with mjit_enabled=true to set the root_fiber's mjit_cont.
    rb_fiber_init_mjit_cont(GET_EC()->fiber_ptr);

    // Initialize class_serials cache for compilation
    valid_class_serials = rb_hash_new();
    rb_obj_hide(valid_class_serials);
    rb_gc_register_mark_object(valid_class_serials);
    mjit_add_class_serial(RCLASS_SERIAL(rb_cObject));
    mjit_add_class_serial(RCLASS_SERIAL(CLASS_OF(rb_vm_top_self())));
    if (RCLASS_CONST_TBL(rb_cObject)) {
        rb_id_table_foreach(RCLASS_CONST_TBL(rb_cObject), valid_class_serials_add_i, NULL);
    }

    // Initialize worker thread
    start_worker();
}

static void
stop_worker(void)
{
    rb_execution_context_t *ec = GET_EC();

    while (!worker_stopped) {
        verbose(3, "Sending cancel signal to worker");
        CRITICAL_SECTION_START(3, "in stop_worker");
        stop_worker_p = true; // Setting this inside loop because RUBY_VM_CHECK_INTS may make this false.
        rb_native_cond_broadcast(&mjit_worker_wakeup);
        CRITICAL_SECTION_FINISH(3, "in stop_worker");
        RUBY_VM_CHECK_INTS(ec);
    }
}

// Stop JIT-compiling methods but compiled code is kept available.
VALUE
mjit_pause(bool wait_p)
{
    if (!mjit_enabled) {
        rb_raise(rb_eRuntimeError, "MJIT is not enabled");
    }
    if (worker_stopped) {
        return Qfalse;
    }

    // Flush all queued units with no option or `wait: true`
    if (wait_p) {
        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 1000;

        while (unit_queue.length > 0 && active_units.length < mjit_opts.max_cache_size) { // inverse of condition that waits for mjit_worker_wakeup
            CRITICAL_SECTION_START(3, "in mjit_pause for a worker wakeup");
            rb_native_cond_broadcast(&mjit_worker_wakeup);
            CRITICAL_SECTION_FINISH(3, "in mjit_pause for a worker wakeup");
            rb_thread_wait_for(tv);
        }
    }

    stop_worker();
    return Qtrue;
}

// Restart JIT-compiling methods after mjit_pause.
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

// Skip calling `clean_temp_files` for units which currently exist in the list.
static void
skip_cleaning_object_files(struct rb_mjit_unit_list *list)
{
    struct rb_mjit_unit *unit = NULL, *next;

    // No mutex for list, assuming MJIT worker does not exist yet since it's immediately after fork.
    list_for_each_safe(&list->head, unit, next, unode) {
#if defined(_WIN32) // mswin doesn't reach here either. This is for MinGW.
        if (unit->so_file) unit->so_file = NULL;
#endif
    }
}

// This is called after fork initiated by Ruby's method to launch MJIT worker thread
// for child Ruby process.
//
// In multi-process Ruby applications, child Ruby processes do most of the jobs.
// Thus we want child Ruby processes to enqueue ISeqs to MJIT worker's queue and
// call the JIT-ed code.
//
// But unfortunately current MJIT-generated code is process-specific. After the fork,
// JIT-ed code created by parent Ruby process cannot be used in child Ruby process
// because the code could rely on inline cache values (ivar's IC, send's CC) which
// may vary between processes after fork or embed some process-specific addresses.
//
// So child Ruby process can't request parent process to JIT an ISeq and use the code.
// Instead of that, MJIT worker thread is created for all child Ruby processes, even
// while child processes would end up with compiling the same ISeqs.
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

// Edit 0 to 1 to enable this feature for investigating hot methods
#define MJIT_COUNTER 0
#if MJIT_COUNTER
static void
mjit_dump_total_calls(void)
{
    struct rb_mjit_unit *unit;
    fprintf(stderr, "[MJIT_COUNTER] total_calls of active_units:\n");
    list_for_each(&active_units.head, unit, unode) {
        const rb_iseq_t *iseq = unit->iseq;
        fprintf(stderr, "%8ld: %s@%s:%d\n", iseq->body->total_calls, RSTRING_PTR(iseq->body->location.label),
                RSTRING_PTR(rb_iseq_path(iseq)), FIX2INT(iseq->body->location.first_lineno));
    }
}
#endif

// Finish the threads processing units and creating PCH, finalize
// and free MJIT data.  It should be called last during MJIT
// life.
//
// If close_handle_p is true, it calls dlclose() for JIT-ed code. So it should be false
// if the code can still be on stack. ...But it means to leak JIT-ed handle forever (FIXME).
void
mjit_finish(bool close_handle_p)
{
    if (!mjit_enabled)
        return;

    // Wait for pch finish
    verbose(2, "Stopping worker thread");
    CRITICAL_SECTION_START(3, "in mjit_finish to wakeup from pch");
    // As our threads are detached, we could just cancel them.  But it
    // is a bad idea because OS processes (C compiler) started by
    // threads can produce temp files.  And even if the temp files are
    // removed, the used C compiler still complaint about their
    // absence.  So wait for a clean finish of the threads.
    while (pch_status == PCH_NOT_READY) {
        verbose(3, "Waiting wakeup from make_pch");
        rb_native_cond_wait(&mjit_pch_wakeup, &mjit_engine_mutex);
    }
    CRITICAL_SECTION_FINISH(3, "in mjit_finish to wakeup from pch");

    // Stop worker
    stop_worker();

    rb_native_mutex_destroy(&mjit_engine_mutex);
    rb_native_cond_destroy(&mjit_pch_wakeup);
    rb_native_cond_destroy(&mjit_client_wakeup);
    rb_native_cond_destroy(&mjit_worker_wakeup);
    rb_native_cond_destroy(&mjit_gc_wakeup);

#if MJIT_COUNTER
    mjit_dump_total_calls();
#endif

#ifndef _MSC_VER // mswin has prebuilt precompiled header
    if (!mjit_opts.save_temps && getpid() == pch_owner_pid)
        remove_file(pch_file);

    xfree(header_file); header_file = NULL;
#endif
    xfree((void *)cc_common_args); cc_common_args = NULL;
    for (char **flag = cc_added_args; *flag != NULL; flag++)
        xfree(*flag);
    xfree((void *)cc_added_args); cc_added_args = NULL;
    xfree(tmp_dir); tmp_dir = NULL;
    xfree(pch_file); pch_file = NULL;

    mjit_call_p = false;
    free_list(&unit_queue, close_handle_p);
    free_list(&active_units, close_handle_p);
    free_list(&compact_units, close_handle_p);
    free_list(&stale_units, close_handle_p);
    finish_conts();

    mjit_enabled = false;
    verbose(1, "Successful MJIT finish");
}

// Called by rb_vm_mark() to mark iseq being JIT-ed and iseqs in the unit queue.
void
mjit_mark(void)
{
    if (!mjit_enabled)
        return;
    RUBY_MARK_ENTER("mjit");

    struct rb_mjit_unit *unit = NULL;
    CRITICAL_SECTION_START(4, "mjit_mark");
    list_for_each(&unit_queue.head, unit, unode) {
        if (unit->iseq) { // ISeq is still not GCed
            VALUE iseq = (VALUE)unit->iseq;
            CRITICAL_SECTION_FINISH(4, "mjit_mark rb_gc_mark");

            // Don't wrap critical section with this. This may trigger GC,
            // and in that case mjit_gc_start_hook causes deadlock.
            rb_gc_mark(iseq);

            CRITICAL_SECTION_START(4, "mjit_mark rb_gc_mark");
        }
    }
    CRITICAL_SECTION_FINISH(4, "mjit_mark");

    RUBY_MARK_LEAVE("mjit");
}

// Called by rb_iseq_mark() to mark cc_entries captured for MJIT
void
mjit_mark_cc_entries(const struct rb_iseq_constant_body *const body)
{
    const struct rb_callcache **cc_entries;
    if (body->jit_unit && (cc_entries = body->jit_unit->cc_entries) != NULL) {
        // It must be `body->jit_unit->cc_entries_size` instead of `body->ci_size` to mark children's cc_entries
        for (unsigned int i = 0; i < body->jit_unit->cc_entries_size; i++) {
            const struct rb_callcache *cc = cc_entries[i];
            if (cc != NULL && vm_cc_markable(cc)) {
                // Pin `cc` and `cc->cme` against GC.compact as their addresses may be written in JIT-ed code.
                rb_gc_mark((VALUE)cc);
                rb_gc_mark((VALUE)vm_cc_cme(cc));
            }
        }
    }
}

// A hook to update valid_class_serials.
void
mjit_add_class_serial(rb_serial_t class_serial)
{
    if (!mjit_enabled)
        return;

    // Do not wrap CRITICAL_SECTION here. This function is only called in main thread
    // and guarded by GVL, and `rb_hash_aset` may cause GC and deadlock in it.
    rb_hash_aset(valid_class_serials, LONG2FIX(class_serial), Qtrue);
}

// A hook to update valid_class_serials.
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
