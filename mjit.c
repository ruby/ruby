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
#include "internal/cmdlineopt.h"
#include "internal/cont.h"
#include "internal/file.h"
#include "internal/hash.h"
#include "internal/warnings.h"
#include "vm_sync.h"
#include "ractor_core.h"

#include "mjit_worker.c"

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

// Prohibit calling JIT-ed code and let existing JIT-ed frames exit before the next insn.
void
mjit_cancel_all(const char *reason)
{
    if (!mjit_enabled)
        return;

    mjit_call_p = false;
    if (mjit_opts.warnings || mjit_opts.verbose) {
        fprintf(stderr, "JIT cancel: Disabled JIT-ed code because %s\n", reason);
    }
}

// Deal with ISeq movement from compactor
void
mjit_update_references(const rb_iseq_t *iseq)
{
    if (!mjit_enabled)
        return;

    CRITICAL_SECTION_START(4, "mjit_update_references");
    if (ISEQ_BODY(iseq)->jit_unit) {
        ISEQ_BODY(iseq)->jit_unit->iseq = (rb_iseq_t *)rb_gc_location((VALUE)ISEQ_BODY(iseq)->jit_unit->iseq);
        // We need to invalidate JIT-ed code for the ISeq because it embeds pointer addresses.
        // To efficiently do that, we use the same thing as TracePoint and thus everything is cancelled for now.
        // See mjit.h and tool/ruby_vm/views/_mjit_compile_insn.erb for how `mjit_call_p` is used.
        mjit_cancel_all("GC.compact is used"); // TODO: instead of cancelling all, invalidate only this one and recompile it with some threshold.
    }

    // Units in stale_units (list of over-speculated and invalidated code) are not referenced from
    // `ISEQ_BODY(iseq)->jit_unit` anymore (because new one replaces that). So we need to check them too.
    // TODO: we should be able to reduce the number of units checked here.
    struct rb_mjit_unit *unit = NULL;
    ccan_list_for_each(&stale_units.head, unit, unode) {
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

    if (ISEQ_BODY(iseq)->jit_unit) {
        // jit_unit is not freed here because it may be referred by multiple
        // lists of units. `get_from_list` and `mjit_finish` do the job.
        ISEQ_BODY(iseq)->jit_unit->iseq = NULL;
    }
    // Units in stale_units (list of over-speculated and invalidated code) are not referenced from
    // `ISEQ_BODY(iseq)->jit_unit` anymore (because new one replaces that). So we need to check them too.
    // TODO: we should be able to reduce the number of units checked here.
    struct rb_mjit_unit *unit = NULL;
    ccan_list_for_each(&stale_units.head, unit, unode) {
        if (unit->iseq == iseq) {
            unit->iseq = NULL;
        }
    }
}

// Free unit list. This should be called only when worker is finished
// because node of unit_queue and one of active_units may have the same unit
// during proceeding unit.
static void
free_list(struct rb_mjit_unit_list *list, bool close_handle_p)
{
    struct rb_mjit_unit *unit = 0, *next;

    ccan_list_for_each_safe(&list->head, unit, next, unode) {
        ccan_list_del(&unit->unode);
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

static void mjit_wait(struct rb_iseq_constant_body *body);

// Check the unit queue and start mjit_compile if nothing is in progress.
static void
check_unit_queue(void)
{
    if (worker_stopped) return;
    if (current_cc_pid != 0) return; // still compiling

    // Run unload_units after it's requested `max_cache_size / 10` (default: 10) times.
    // This throttles the call to mitigate locking in unload_units. It also throttles JIT compaction.
    int throttle_threshold = mjit_opts.max_cache_size / 10;
    if (unload_requests >= throttle_threshold) {
        unload_units();
        unload_requests = 0;
        if (active_units.length == mjit_opts.max_cache_size && mjit_opts.wait) { // Sometimes all methods may be in use
            mjit_opts.max_cache_size++; // avoid infinite loop on `rb_mjit_wait_call`. Note that --jit-wait is just for testing.
            verbose(1, "No units can be unloaded -- incremented max-cache-size to %d for --jit-wait", mjit_opts.max_cache_size);
        }
    }
    if (active_units.length >= mjit_opts.max_cache_size) return; // wait until unload_units makes a progress

    // Dequeue a unit
    struct rb_mjit_unit *unit = get_from_list(&unit_queue);
    if (unit == NULL) return;

#ifdef _WIN32
    // Synchronously compile methods on Windows.
    // mswin: No SIGCHLD, MinGW: directly compiling .c to .so doesn't work
    mjit_func_t func = convert_unit_to_func(unit);
    MJIT_ATOMIC_SET(ISEQ_BODY(unit->iseq)->jit_func, func);
    if ((uintptr_t)func > (uintptr_t)LAST_JIT_ISEQ_FUNC) {
        add_to_list(unit, &active_units);
    }
#else
    current_cc_ms = real_ms_time();
    current_cc_unit = unit;
    current_cc_pid = start_mjit_compile(unit);

    // JIT failure
    if (current_cc_pid == -1) {
        current_cc_pid = 0;
        current_cc_unit->iseq->body->jit_func = (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC; // TODO: consider unit->compact_p
        current_cc_unit = NULL;
        return;
    }

    if (mjit_opts.wait) {
        mjit_wait(unit->iseq->body);
    }
#endif
}

// Create unit for `iseq`. This function may be called from an MJIT worker.
static struct rb_mjit_unit*
create_unit(const rb_iseq_t *iseq)
{
    // To prevent GC, don't use ZALLOC // TODO: just use ZALLOC
    struct rb_mjit_unit *unit = calloc(1, sizeof(struct rb_mjit_unit));
    if (unit == NULL)
        return NULL;

    unit->id = current_unit_num++;
    if (iseq == NULL) { // Compact unit
        unit->compact_p = true;
    } else { // Normal unit
        unit->iseq = (rb_iseq_t *)iseq;
        ISEQ_BODY(iseq)->jit_unit = unit;
    }
    return unit;
}

// Check if it should compact all JIT code and start it as needed
static void
check_compaction(void)
{
#if USE_JIT_COMPACTION
    // Allow only `max_cache_size / 100` times (default: 100) of compaction.
    // Note: GC of compacted code has not been implemented yet.
    int max_compact_size = mjit_opts.max_cache_size / 100;
    if (max_compact_size < 10) max_compact_size = 10;

    // Run unload_units after it's requested `max_cache_size / 10` (default: 10) times.
    // This throttles the call to mitigate locking in unload_units. It also throttles JIT compaction.
    int throttle_threshold = mjit_opts.max_cache_size / 10;

    if (compact_units.length < max_compact_size
        && ((!mjit_opts.wait && unit_queue.length == 0 && active_units.length > 1)
            || (active_units.length == mjit_opts.max_cache_size && compact_units.length * throttle_threshold <= total_unloads))) { // throttle compaction by total_unloads
        struct rb_mjit_unit *unit = create_unit(NULL);
        if (unit != NULL) {
            // TODO: assert unit is null
            current_cc_ms = real_ms_time();
            current_cc_unit = unit;
            current_cc_pid = start_mjit_compact(unit);
            // TODO: check -1
        }
    }
#endif
}

// Check the current CC process if any, and start a next C compiler process as needed.
void
mjit_notify_waitpid(int status)
{
    // TODO: check current_cc_pid?
    current_cc_pid = 0;

    // Delete .c file
    char c_file[MAXPATHLEN];
    sprint_uniq_filename(c_file, (int)sizeof(c_file), current_cc_unit->id, MJIT_TMP_PREFIX, ".c");
    if (!mjit_opts.save_temps)
        remove_file(c_file);

    // Check the result
    bool success = false;
    if (WIFEXITED(status)) {
        success = (WEXITSTATUS(status) == 0);
    }
    if (!success) {
        verbose(2, "Failed to generate so");
        if (!current_cc_unit->compact_p) {
            current_cc_unit->iseq->body->jit_func = (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
        }
        free_unit(current_cc_unit);
        current_cc_unit = NULL;
        return;
    }

    // Load .so file
    char so_file[MAXPATHLEN];
    sprint_uniq_filename(so_file, (int)sizeof(so_file), current_cc_unit->id, MJIT_TMP_PREFIX, DLEXT);
    if (current_cc_unit->compact_p) { // Compact unit
#if USE_JIT_COMPACTION
        load_compact_funcs_from_so(current_cc_unit, c_file, so_file);
        current_cc_unit = NULL;
#else
        RUBY_ASSERT(!current_cc_unit->compact_p);
#endif
    }
    else { // Normal unit
        // Load the function from so
        char funcname[MAXPATHLEN];
        sprint_funcname(funcname, current_cc_unit);
        void *func = load_func_from_so(so_file, funcname, current_cc_unit);

        // Delete .so file
        if (!mjit_opts.save_temps)
            remove_file(so_file);

        // Set the jit_func if successful
        if (current_cc_unit->iseq != NULL) { // mjit_free_iseq could nullify this
            rb_iseq_t *iseq = current_cc_unit->iseq;
            if ((uintptr_t)func > (uintptr_t)LAST_JIT_ISEQ_FUNC) {
                double end_time = real_ms_time();
                verbose(1, "JIT success (%.1fms): %s@%s:%ld -> %s",
                        end_time - current_cc_ms, RSTRING_PTR(ISEQ_BODY(iseq)->location.label),
                        RSTRING_PTR(rb_iseq_path(iseq)), FIX2LONG(ISEQ_BODY(iseq)->location.first_lineno), c_file);

                add_to_list(current_cc_unit, &active_units);
            }
            MJIT_ATOMIC_SET(ISEQ_BODY(iseq)->jit_func, func);
        } // TODO: free unit on else?
        current_cc_unit = NULL;

        // Run compaction if it should
        if (!stop_worker_p) {
            check_compaction();
        }
    }

    // Skip further compilation if mjit_finish is trying to stop it
    if (!stop_worker_p) {
        // Start the next one as needed
        check_unit_queue();
    }
}

// Return true if given ISeq body should be compiled by MJIT
static inline int
mjit_target_iseq_p(const rb_iseq_t *iseq)
{
    struct rb_iseq_constant_body *body = ISEQ_BODY(iseq);
    return (body->type == ISEQ_TYPE_METHOD || body->type == ISEQ_TYPE_BLOCK)
        && !body->builtin_inline_p
        && strcmp("<internal:mjit>", RSTRING_PTR(rb_iseq_path(iseq)));
}

// If recompile_p is true, the call is initiated by mjit_recompile.
// This assumes the caller holds CRITICAL_SECTION when recompile_p is true.
static void
mjit_add_iseq_to_process(const rb_iseq_t *iseq, const struct rb_mjit_compile_info *compile_info, bool recompile_p)
{
    // TODO: Support non-main Ractors
    if (!mjit_enabled || pch_status == PCH_FAILED || !rb_ractor_main_p())
        return;
    if (!mjit_target_iseq_p(iseq)) {
        ISEQ_BODY(iseq)->jit_func = (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC; // skip mjit_wait
        return;
    }

    RB_DEBUG_COUNTER_INC(mjit_add_iseq_to_process);
    ISEQ_BODY(iseq)->jit_func = (mjit_func_t)NOT_READY_JIT_ISEQ_FUNC;
    create_unit(iseq);
    if (ISEQ_BODY(iseq)->jit_unit == NULL)
        // Failure in creating the unit.
        return;
    if (compile_info != NULL)
        ISEQ_BODY(iseq)->jit_unit->compile_info = *compile_info;
    add_to_list(ISEQ_BODY(iseq)->jit_unit, &unit_queue);
    if (active_units.length >= mjit_opts.max_cache_size) {
        unload_requests++;
    }
}

// Add ISEQ to be JITed in parallel with the current thread.
// Unload some JIT codes if there are too many of them.
void
rb_mjit_add_iseq_to_process(const rb_iseq_t *iseq)
{
    mjit_add_iseq_to_process(iseq, NULL, false);
    check_unit_queue();
}

// For this timeout seconds, --jit-wait will wait for JIT compilation finish.
#define MJIT_WAIT_TIMEOUT_SECONDS 60

static void
mjit_wait(struct rb_iseq_constant_body *body)
{
    pid_t initial_pid = current_cc_pid;
    struct timeval tv;
    int tries = 0;
    tv.tv_sec = 0;
    tv.tv_usec = 1000;
    while (body == NULL ? current_cc_pid == initial_pid : body->jit_func == (mjit_func_t)NOT_READY_JIT_ISEQ_FUNC) { // TODO: refactor this
        tries++;
        if (tries / 1000 > MJIT_WAIT_TIMEOUT_SECONDS || pch_status == PCH_FAILED) {
            if (body != NULL) {
                body->jit_func = (mjit_func_t) NOT_COMPILED_JIT_ISEQ_FUNC; // JIT worker seems dead. Give up.
            }
            mjit_warning("timed out to wait for JIT finish");
            break;
        }

        rb_thread_wait_for(tv);
    }
}

static void
mjit_wait_unit(struct rb_mjit_unit *unit)
{
    if (unit->compact_p) {
        mjit_wait(NULL);
    }
    else {
        mjit_wait(current_cc_unit->iseq->body);
    }
}

// Wait for JIT compilation finish for --jit-wait, and call the function pointer
// if the compiled result is not NOT_COMPILED_JIT_ISEQ_FUNC.
VALUE
rb_mjit_wait_call(rb_execution_context_t *ec, struct rb_iseq_constant_body *body)
{
    if (worker_stopped)
        return Qundef;

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
    if ((uintptr_t)ISEQ_BODY(iseq)->jit_func <= (uintptr_t)LAST_JIT_ISEQ_FUNC)
        return;

    verbose(1, "JIT recompile: %s@%s:%d", RSTRING_PTR(ISEQ_BODY(iseq)->location.label),
            RSTRING_PTR(rb_iseq_path(iseq)), FIX2INT(ISEQ_BODY(iseq)->location.first_lineno));
    assert(ISEQ_BODY(iseq)->jit_unit != NULL);

    mjit_add_iseq_to_process(iseq, &ISEQ_BODY(iseq)->jit_unit->compile_info, true);
    check_unit_queue();
}

// Recompile iseq, disabling send optimization
void
rb_mjit_recompile_send(const rb_iseq_t *iseq)
{
    rb_mjit_iseq_compile_info(ISEQ_BODY(iseq))->disable_send_cache = true;
    mjit_recompile(iseq);
}

// Recompile iseq, disabling ivar optimization
void
rb_mjit_recompile_ivar(const rb_iseq_t *iseq)
{
    rb_mjit_iseq_compile_info(ISEQ_BODY(iseq))->disable_ivar_cache = true;
    mjit_recompile(iseq);
}

// Recompile iseq, disabling exivar optimization
void
rb_mjit_recompile_exivar(const rb_iseq_t *iseq)
{
    rb_mjit_iseq_compile_info(ISEQ_BODY(iseq))->disable_exivar_cache = true;
    mjit_recompile(iseq);
}

// Recompile iseq, disabling method inlining
void
rb_mjit_recompile_inlining(const rb_iseq_t *iseq)
{
    rb_mjit_iseq_compile_info(ISEQ_BODY(iseq))->disable_inlining = true;
    mjit_recompile(iseq);
}

// Recompile iseq, disabling getconstant inlining
void
rb_mjit_recompile_const(const rb_iseq_t *iseq)
{
    rb_mjit_iseq_compile_info(ISEQ_BODY(iseq))->disable_const_cache = true;
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
#define DEFAULT_MAX_CACHE_SIZE 10000
// A default threshold used to add iseq to JIT.
#define DEFAULT_MIN_CALLS_TO_ADD 10000

// Start MJIT worker. Return TRUE if worker is successfully started.
static bool
start_worker(void)
{
    stop_worker_p = false;
    worker_stopped = false;
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

#define opt_match_noarg(s, l, name) \
    opt_match(s, l, name) && (*(s) ? (rb_warn("argument to --mjit-" name " is ignored"), 1) : 1)
#define opt_match_arg(s, l, name) \
    opt_match(s, l, name) && (*(s) ? 1 : (rb_raise(rb_eRuntimeError, "--mjit-" name " needs an argument"), 0))

void
mjit_setup_options(const char *s, struct mjit_options *mjit_opt)
{
    const size_t l = strlen(s);
    if (l == 0) {
        return;
    }
    else if (opt_match_noarg(s, l, "warnings")) {
        mjit_opt->warnings = 1;
    }
    else if (opt_match(s, l, "debug")) {
        if (*s)
            mjit_opt->debug_flags = strdup(s + 1);
        else
            mjit_opt->debug = 1;
    }
    else if (opt_match_noarg(s, l, "wait")) {
        mjit_opt->wait = 1;
    }
    else if (opt_match_noarg(s, l, "save-temps")) {
        mjit_opt->save_temps = 1;
    }
    else if (opt_match(s, l, "verbose")) {
        mjit_opt->verbose = *s ? atoi(s + 1) : 1;
    }
    else if (opt_match_arg(s, l, "max-cache")) {
        mjit_opt->max_cache_size = atoi(s + 1);
    }
    else if (opt_match_arg(s, l, "min-calls")) {
        mjit_opt->min_calls = atoi(s + 1);
    }
    else {
        rb_raise(rb_eRuntimeError,
                 "invalid MJIT option `%s' (--help will show valid MJIT options)", s);
    }
}

#define M(shortopt, longopt, desc) RUBY_OPT_MESSAGE(shortopt, longopt, desc)
const struct ruby_opt_message mjit_option_messages[] = {
    M("--mjit-warnings",      "", "Enable printing JIT warnings"),
    M("--mjit-debug",         "", "Enable JIT debugging (very slow), or add cflags if specified"),
    M("--mjit-wait",          "", "Wait until JIT compilation finishes every time (for testing)"),
    M("--mjit-save-temps",    "", "Save JIT temporary files in $TMP or /tmp (for testing)"),
    M("--mjit-verbose=num",   "", "Print JIT logs of level num or less to stderr (default: 0)"),
    M("--mjit-max-cache=num", "", "Max number of methods to be JIT-ed in a cache (default: "
      STRINGIZE(DEFAULT_MAX_CACHE_SIZE) ")"),
    M("--mjit-min-calls=num", "", "Number of calls to trigger JIT (for testing, default: "
      STRINGIZE(DEFAULT_MIN_CALLS_TO_ADD) ")"),
    {0}
};
#undef M

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

    // Initialize worker thread
    start_worker();

#ifndef _MSC_VER
    // TODO: Consider running C compiler asynchronously
    make_pch();
#endif
}

static void
stop_worker(void)
{
    stop_worker_p = true;
    if (current_cc_unit != NULL) {
        mjit_wait_unit(current_cc_unit);
    }
    worker_stopped = true;
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
        while (current_cc_unit != NULL) {
            mjit_wait_unit(current_cc_unit);
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
    ccan_list_for_each(&active_units.head, unit, unode) {
        const rb_iseq_t *iseq = unit->iseq;
        fprintf(stderr, "%8ld: %s@%s:%d\n", ISEQ_BODY(iseq)->total_calls, RSTRING_PTR(ISEQ_BODY(iseq)->location.label),
                RSTRING_PTR(rb_iseq_path(iseq)), FIX2INT(ISEQ_BODY(iseq)->location.first_lineno));
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

    // Stop worker
    verbose(2, "Stopping worker thread");
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

// Called by rb_vm_mark().
//
// Mark active_units so that we do not GC ISeq which may still be
// referenced by mjit_recompile() or mjit_compact().
void
mjit_mark(void)
{
    if (!mjit_enabled)
        return;
    RUBY_MARK_ENTER("mjit");

    struct rb_mjit_unit *unit = NULL;
    ccan_list_for_each(&active_units.head, unit, unode) {
        rb_gc_mark((VALUE)unit->iseq);
    }

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

#include "mjit.rbinc"

#endif // USE_MJIT
