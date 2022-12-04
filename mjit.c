/**********************************************************************

  mjit.c - MRI method JIT compiler functions for Ruby's main thread

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.

**********************************************************************/

/* We utilize widely used C compilers (GCC and LLVM Clang) to
   implement MJIT.  We feed them a C code generated from ISEQ.  The
   industrial C compilers are slower than regular JIT engines.
   Generated code performance of the used C compilers has a higher
   priority over the compilation speed.

   So our major goal is to minimize the ISEQ compilation time when we
   use widely optimization level (-O2).  It is achieved by

   o Using a precompiled version of the header
   o Keeping all files in `/tmp`.  On modern Linux `/tmp` is a file
     system in memory. So it is pretty fast
   o Implementing MJIT as a multi-threaded code because we want to
     compile ISEQs in parallel with iseq execution to speed up Ruby
     code execution.  MJIT has one thread (*worker*) to do
     parallel compilations:
      o It prepares a precompiled code of the minimized header.
        It starts at the MRI execution start
      o It generates PIC object files of ISEQs
      o It takes one JIT unit from a priority queue unless it is empty.
      o It translates the JIT unit ISEQ into C-code using the precompiled
        header, calls CC and load PIC code when it is ready
      o Currently MJIT put ISEQ in the queue when ISEQ is called
      o MJIT can reorder ISEQs in the queue if some ISEQ has been called
        many times and its compilation did not start yet
      o MRI reuses the machine code if it already exists for ISEQ
      o The machine code we generate can stop and switch to the ISEQ
        interpretation if some condition is not satisfied as the machine
        code can be speculative or some exception raises
      o Speculative machine code can be canceled.

   Here is a diagram showing the MJIT organization:

                 _______
                |header |
                |_______|
                    |                         MRI building
      --------------|----------------------------------------
                    |                         MRI execution
                    |
       _____________|_____
      |             |     |
      |          ___V__   |  CC      ____________________
      |         |      |----------->| precompiled header |
      |         |      |  |         |____________________|
      |         |      |  |              |
      |         | MJIT |  |              |
      |         |      |  |              |
      |         |      |  |          ____V___  CC  __________
      |         |______|----------->| C code |--->| .so file |
      |                   |         |________|    |__________|
      |                   |                              |
      |                   |                              |
      | MRI machine code  |<-----------------------------
      |___________________|             loading

*/

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
#include "internal/process.h"
#include "internal/warnings.h"
#include "vm_sync.h"
#include "ractor_core.h"

#ifdef __sun
#define __EXTENSIONS__ 1
#endif

#include "vm_core.h"
#include "vm_callinfo.h"
#include "mjit.h"
#include "mjit_c.h"
#include "gc.h"
#include "ruby_assert.h"
#include "ruby/debug.h"
#include "ruby/thread.h"
#include "ruby/version.h"
#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"
#include "internal/compile.h"

#include <sys/wait.h>
#include <sys/time.h>
#include <dlfcn.h>
#include <errno.h>
#ifdef HAVE_FCNTL_H
#include <fcntl.h>
#endif
#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#endif
#include "dln.h"

#include "ruby/util.h"
#undef strdup // ruby_strdup may trigger GC

#ifndef MAXPATHLEN
# define MAXPATHLEN 1024
#endif

// Atomically set function pointer if possible.
#define MJIT_ATOMIC_SET(var, val) (void)ATOMIC_PTR_EXCHANGE(var, val)

#define MJIT_TMP_PREFIX "_ruby_mjit_"

// Linked list of struct rb_mjit_unit.
struct rb_mjit_unit_list {
    struct ccan_list_head head;
    int length; // the list length
};

extern void rb_native_mutex_lock(rb_nativethread_lock_t *lock);
extern void rb_native_mutex_unlock(rb_nativethread_lock_t *lock);
extern void rb_native_mutex_initialize(rb_nativethread_lock_t *lock);
extern void rb_native_mutex_destroy(rb_nativethread_lock_t *lock);

extern void rb_native_cond_initialize(rb_nativethread_cond_t *cond);
extern void rb_native_cond_destroy(rb_nativethread_cond_t *cond);
extern void rb_native_cond_signal(rb_nativethread_cond_t *cond);
extern void rb_native_cond_broadcast(rb_nativethread_cond_t *cond);
extern void rb_native_cond_wait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex);

// process.c
extern void mjit_add_waiting_pid(rb_vm_t *vm, rb_pid_t pid);

// A copy of MJIT portion of MRI options since MJIT initialization.  We
// need them as MJIT threads still can work when the most MRI data were
// freed.
struct mjit_options mjit_opts;

// true if MJIT is enabled.
bool mjit_enabled = false;
// true if JIT-ed code should be called. When `ruby_vm_event_enabled_global_flags & ISEQ_TRACE_EVENTS`
// and `mjit_call_p == false`, any JIT-ed code execution is cancelled as soon as possible.
bool mjit_call_p = false;

// Priority queue of iseqs waiting for JIT compilation.
// This variable is a pointer to head unit of the queue.
static struct rb_mjit_unit_list unit_queue = { CCAN_LIST_HEAD_INIT(unit_queue.head) };
// List of units which are successfully compiled.
static struct rb_mjit_unit_list active_units = { CCAN_LIST_HEAD_INIT(active_units.head) };
// List of compacted so files which will be cleaned up by `free_list()` in `mjit_finish()`.
static struct rb_mjit_unit_list compact_units = { CCAN_LIST_HEAD_INIT(compact_units.head) };
// List of units before recompilation and just waiting for dlclose().
static struct rb_mjit_unit_list stale_units = { CCAN_LIST_HEAD_INIT(stale_units.head) };
// The number of so far processed ISEQs, used to generate unique id.
static int current_unit_num;
// A mutex for conitionals and critical sections.
static rb_nativethread_lock_t mjit_engine_mutex;
// A thread conditional to wake up `mjit_finish` at the end of PCH thread.
static rb_nativethread_cond_t mjit_pch_wakeup;
// A thread conditional to wake up the client if there is a change in
// executed unit status.
static rb_nativethread_cond_t mjit_client_wakeup;
// A thread conditional to wake up a worker if there we have something
// to add or we need to stop MJIT engine.
static rb_nativethread_cond_t mjit_worker_wakeup;
// A thread conditional to wake up workers if at the end of GC.
static rb_nativethread_cond_t mjit_gc_wakeup;
// The times when unload_units is requested. unload_units is called after some requests.
static int unload_requests = 0;
// The total number of unloaded units.
static int total_unloads = 0;
// Set to true to stop worker.
static bool stop_worker_p;
// Set to true if worker is stopped.
static bool worker_stopped = true;

// Path of "/tmp", which is different on Windows or macOS. See: system_default_tmpdir()
static char *tmp_dir;

// Used C compiler path.
static const char *cc_path;
// Used C compiler flags.
static const char **cc_common_args;
// Used C compiler flags added by --mjit-debug=...
static char **cc_added_args;
// Name of the precompiled header file.
static char *pch_file;
// The process id which should delete the pch_file on mjit_finish.
static rb_pid_t pch_owner_pid;
// Status of the precompiled header creation.  The status is
// shared by the workers and the pch thread.
static enum {PCH_NOT_READY, PCH_FAILED, PCH_SUCCESS} pch_status;

// The start timestamp of current compilation
static double current_cc_ms = 0.0; // TODO: make this part of unit?
// Currently compiling MJIT unit
static struct rb_mjit_unit *current_cc_unit = NULL;
// PID of currently running C compiler process. 0 if nothing is running.
static pid_t current_cc_pid = 0; // TODO: make this part of unit?

// Name of the header file.
static char *header_file;

#include "mjit_config.h"

#if defined(__GNUC__) && \
     (!defined(__clang__) || \
      (defined(__clang__) && (defined(__FreeBSD__) || defined(__GLIBC__))))
# define GCC_PIC_FLAGS "-Wfatal-errors", "-fPIC", "-shared", "-w", "-pipe",
# define MJIT_CFLAGS_PIPE 1
#else
# define GCC_PIC_FLAGS /* empty */
# define MJIT_CFLAGS_PIPE 0
#endif

// Use `-nodefaultlibs -nostdlib` for GCC where possible, which does not work on cygwin, AIX, and OpenBSD.
// This seems to improve MJIT performance on GCC.
#if defined __GNUC__ && !defined __clang__ && !defined(__CYGWIN__) && !defined(_AIX) && !defined(__OpenBSD__)
# define GCC_NOSTDLIB_FLAGS "-nodefaultlibs", "-nostdlib",
#else
# define GCC_NOSTDLIB_FLAGS // empty
#endif

static const char *const CC_COMMON_ARGS[] = {
    MJIT_CC_COMMON MJIT_CFLAGS GCC_PIC_FLAGS
    NULL
};

static const char *const CC_DEBUG_ARGS[] = {MJIT_DEBUGFLAGS NULL};
static const char *const CC_OPTIMIZE_ARGS[] = {MJIT_OPTFLAGS NULL};

static const char *const CC_LDSHARED_ARGS[] = {MJIT_LDSHARED MJIT_CFLAGS GCC_PIC_FLAGS NULL};
static const char *const CC_DLDFLAGS_ARGS[] = {MJIT_DLDFLAGS NULL};
// `CC_LINKER_ARGS` are linker flags which must be passed to `-c` as well.
static const char *const CC_LINKER_ARGS[] = {
#if defined __GNUC__ && !defined __clang__ && !defined(__OpenBSD__)
    "-nostartfiles",
#endif
    GCC_NOSTDLIB_FLAGS NULL
};

static const char *const CC_LIBS[] = {
#if defined(__CYGWIN__)
    MJIT_LIBS // mswin, cygwin
#endif
#if defined __GNUC__ && !defined __clang__
    "-lgcc", // cygwin, and GCC platforms using `-nodefaultlibs -nostdlib`
#endif
#if defined __ANDROID__
    "-lm", // to avoid 'cannot locate symbol "modf" referenced by .../_ruby_mjit_XXX.so"'
#endif
    NULL
};

#define CC_CODEFLAG_ARGS (mjit_opts.debug ? CC_DEBUG_ARGS : CC_OPTIMIZE_ARGS)

// Print the arguments according to FORMAT to stderr only if MJIT
// verbose option value is more or equal to LEVEL.
PRINTF_ARGS(static void, 2, 3)
verbose(int level, const char *format, ...)
{
    if (mjit_opts.verbose >= level) {
        va_list args;
        size_t len = strlen(format);
        char *full_format = alloca(sizeof(char) * (len + 2));

        // Creating `format + '\n'` to atomically print format and '\n'.
        memcpy(full_format, format, len);
        full_format[len] = '\n';
        full_format[len+1] = '\0';

        va_start(args, format);
        vfprintf(stderr, full_format, args);
        va_end(args);
    }
}

PRINTF_ARGS(static void, 1, 2)
mjit_warning(const char *format, ...)
{
    if (mjit_opts.warnings || mjit_opts.verbose) {
        va_list args;

        fprintf(stderr, "MJIT warning: ");
        va_start(args, format);
        vfprintf(stderr, format, args);
        va_end(args);
        fprintf(stderr, "\n");
    }
}

// Add unit node to the tail of doubly linked `list`. It should be not in
// the list before.
static void
add_to_list(struct rb_mjit_unit *unit, struct rb_mjit_unit_list *list)
{
    (void)RB_DEBUG_COUNTER_INC_IF(mjit_length_unit_queue, list == &unit_queue);
    (void)RB_DEBUG_COUNTER_INC_IF(mjit_length_active_units, list == &active_units);
    (void)RB_DEBUG_COUNTER_INC_IF(mjit_length_compact_units, list == &compact_units);
    (void)RB_DEBUG_COUNTER_INC_IF(mjit_length_stale_units, list == &stale_units);

    ccan_list_add_tail(&list->head, &unit->unode);
    list->length++;
}

static void
remove_from_list(struct rb_mjit_unit *unit, struct rb_mjit_unit_list *list)
{
#if USE_DEBUG_COUNTER
    rb_debug_counter_add(RB_DEBUG_COUNTER_mjit_length_unit_queue, -1, list == &unit_queue);
    rb_debug_counter_add(RB_DEBUG_COUNTER_mjit_length_active_units, -1, list == &active_units);
    rb_debug_counter_add(RB_DEBUG_COUNTER_mjit_length_compact_units, -1, list == &compact_units);
    rb_debug_counter_add(RB_DEBUG_COUNTER_mjit_length_stale_units, -1, list == &stale_units);
#endif

    ccan_list_del(&unit->unode);
    list->length--;
}

static void
remove_file(const char *filename)
{
    if (remove(filename)) {
        mjit_warning("failed to remove \"%s\": %s", filename, strerror(errno));
    }
}

// This is called in the following situations:
// 1) On dequeue or `unload_units()`, associated ISeq is already GCed.
// 2) The unit is not called often and unloaded by `unload_units()`.
// 3) Freeing lists on `mjit_finish()`.
//
// `jit_func` value does not matter for 1 and 3 since the unit won't be used anymore.
// For the situation 2, this sets the ISeq's JIT state to NOT_COMPILED_JIT_ISEQ_FUNC
// to prevent the situation that the same methods are continuously compiled.
static void
free_unit(struct rb_mjit_unit *unit)
{
    if (unit->iseq) { // ISeq is not GCed
        ISEQ_BODY(unit->iseq)->jit_func = (jit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
        ISEQ_BODY(unit->iseq)->jit_unit = NULL;
    }
    if (unit->cc_entries) {
        void *entries = (void *)unit->cc_entries;
        free(entries);
    }
    if (unit->handle && dlclose(unit->handle)) { // handle is NULL if it's in queue
        mjit_warning("failed to close handle for u%d: %s", unit->id, dlerror());
    }
    free(unit);
}

// Start a critical section. Use message `msg` to print debug info at `level`.
static inline void
CRITICAL_SECTION_START(int level, const char *msg)
{
    verbose(level, "Locking %s", msg);
    rb_native_mutex_lock(&mjit_engine_mutex);
    verbose(level, "Locked %s", msg);
}

// Finish the current critical section. Use message `msg` to print
// debug info at `level`.
static inline void
CRITICAL_SECTION_FINISH(int level, const char *msg)
{
    verbose(level, "Unlocked %s", msg);
    rb_native_mutex_unlock(&mjit_engine_mutex);
}

static pid_t mjit_pid = 0;

static int
sprint_uniq_filename(char *str, size_t size, unsigned long id, const char *prefix, const char *suffix)
{
    return snprintf(str, size, "%s/%sp%"PRI_PIDT_PREFIX"uu%lu%s", tmp_dir, prefix, mjit_pid, id, suffix);
}

// Return time in milliseconds as a double.
#ifdef __APPLE__
double ruby_real_ms_time(void);
# define real_ms_time() ruby_real_ms_time()
#else
static double
real_ms_time(void)
{
# ifdef HAVE_CLOCK_GETTIME
    struct timespec  tv;
#  ifdef CLOCK_MONOTONIC
    const clockid_t c = CLOCK_MONOTONIC;
#  else
    const clockid_t c = CLOCK_REALTIME;
#  endif

    clock_gettime(c, &tv);
    return tv.tv_nsec / 1000000.0 + tv.tv_sec * 1000.0;
# else
    struct timeval  tv;

    gettimeofday(&tv, NULL);
    return tv.tv_usec / 1000.0 + tv.tv_sec * 1000.0;
# endif
}
#endif

// Return the best unit from list.  The best is the first
// high priority unit or the unit whose iseq has the biggest number
// of calls so far.
static struct rb_mjit_unit *
get_from_list(struct rb_mjit_unit_list *list)
{
    // Find iseq with max total_calls
    struct rb_mjit_unit *unit = NULL, *next, *best = NULL;
    ccan_list_for_each_safe(&list->head, unit, next, unode) {
        if (unit->iseq == NULL) { // ISeq is GCed.
            remove_from_list(unit, list);
            free_unit(unit);
            continue;
        }

        if (best == NULL || ISEQ_BODY(best->iseq)->total_calls < ISEQ_BODY(unit->iseq)->total_calls) {
            best = unit;
        }
    }

    if (best) {
        remove_from_list(best, list);
    }
    return best;
}

// Return length of NULL-terminated array `args` excluding the NULL marker.
static size_t
args_len(char *const *args)
{
    size_t i;

    for (i = 0; (args[i]) != NULL;i++)
        ;
    return i;
}

// Concatenate `num` passed NULL-terminated arrays of strings, put the
// result (with NULL end marker) into the heap, and return the result.
static char **
form_args(int num, ...)
{
    va_list argp;
    size_t len, n;
    int i;
    char **args, **res, **tmp;

    va_start(argp, num);
    res = NULL;
    for (i = len = 0; i < num; i++) {
        args = va_arg(argp, char **);
        n = args_len(args);
        if ((tmp = (char **)realloc(res, sizeof(char *) * (len + n + 1))) == NULL) {
            free(res);
            res = NULL;
            break;
        }
        res = tmp;
        MEMCPY(res + len, args, char *, n + 1);
        len += n;
    }
    va_end(argp);
    return res;
}

COMPILER_WARNING_PUSH
#if __has_warning("-Wdeprecated-declarations") || RBIMPL_COMPILER_IS(GCC)
COMPILER_WARNING_IGNORED(-Wdeprecated-declarations)
#endif
// Start an OS process of absolute executable path with arguments `argv`.
// Return PID of the process.
static pid_t
start_process(const char *abspath, char *const *argv)
{
    // Not calling non-async-signal-safe functions between vfork
    // and execv for safety
    int dev_null = rb_cloexec_open(ruby_null_device, O_WRONLY, 0);
    if (dev_null < 0) {
        verbose(1, "MJIT: Failed to open a null device: %s", strerror(errno));
        return -1;
    }
    if (mjit_opts.verbose >= 2) {
        const char *arg;
        fprintf(stderr, "Starting process: %s", abspath);
        for (int i = 0; (arg = argv[i]) != NULL; i++)
            fprintf(stderr, " %s", arg);
        fprintf(stderr, "\n");
    }

    pid_t pid;
    if ((pid = vfork()) == 0) { /* TODO: reuse some function in process.c */
        umask(0077);
        if (mjit_opts.verbose == 0) {
            // CC can be started in a thread using a file which has been
            // already removed while MJIT is finishing.  Discard the
            // messages about missing files.
            dup2(dev_null, STDERR_FILENO);
            dup2(dev_null, STDOUT_FILENO);
        }
        (void)close(dev_null);
        pid = execv(abspath, argv); // Pid will be negative on an error
        // Even if we successfully found CC to compile PCH we still can
        // fail with loading the CC in very rare cases for some reasons.
        // Stop the forked process in this case.
        verbose(1, "MJIT: Error in execv: %s", abspath);
        _exit(1);
    }
    (void)close(dev_null);
    return pid;
}
COMPILER_WARNING_POP

// Execute an OS process of executable PATH with arguments ARGV.
// Return -1 or -2 if failed to execute, otherwise exit code of the process.
// TODO: Use a similar function in process.c
static int
exec_process(const char *path, char *const argv[])
{
    int stat, exit_code = -2;
    pid_t pid = start_process(path, argv);
    for (;pid > 0;) {
        pid_t r = waitpid(pid, &stat, 0);
        if (r == -1) {
            if (errno == EINTR) continue;
            fprintf(stderr, "[%"PRI_PIDT_PREFIX"d] waitpid(%lu): %s (SIGCHLD=%d,%u)\n",
                    getpid(), (unsigned long)pid, strerror(errno),
                    RUBY_SIGCHLD, SIGCHLD_LOSSY);
            break;
        }
        else if (r == pid) {
            if (WIFEXITED(stat)) {
                exit_code = WEXITSTATUS(stat);
                break;
            }
            else if (WIFSIGNALED(stat)) {
                exit_code = -1;
                break;
            }
        }
    }
    return exit_code;
}

static void
remove_so_file(const char *so_file, struct rb_mjit_unit *unit)
{
    remove_file(so_file);
}

// Print _mjitX, but make a human-readable funcname when --mjit-debug is used
static void
sprint_funcname(char *funcname, size_t funcname_size, const struct rb_mjit_unit *unit)
{
    const rb_iseq_t *iseq = unit->iseq;
    if (iseq == NULL || (!mjit_opts.debug && !mjit_opts.debug_flags)) {
        snprintf(funcname, funcname_size, "_mjit%d", unit->id);
        return;
    }

    // Generate a short path
    const char *path = RSTRING_PTR(rb_iseq_path(iseq));
    const char *lib = "/lib/";
    const char *version = "/" STRINGIZE(RUBY_API_VERSION_MAJOR) "." STRINGIZE(RUBY_API_VERSION_MINOR) "." STRINGIZE(RUBY_API_VERSION_TEENY) "/";
    while (strstr(path, lib)) // skip "/lib/"
        path = strstr(path, lib) + strlen(lib);
    while (strstr(path, version)) // skip "/x.y.z/"
        path = strstr(path, version) + strlen(version);

    // Annotate all-normalized method names
    const char *method = RSTRING_PTR(ISEQ_BODY(iseq)->location.label);
    if (!strcmp(method, "[]")) method = "AREF";
    if (!strcmp(method, "[]=")) method = "ASET";

    // Print and normalize
    snprintf(funcname, funcname_size, "_mjit%d_%s_%s", unit->id, path, method);
    for (size_t i = 0; i < strlen(funcname); i++) {
        char c = funcname[i];
        if (!(('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || ('0' <= c && c <= '9') || c == '_')) {
            funcname[i] = '_';
        }
    }
}

static const int c_file_access_mode =
#ifdef O_BINARY
    O_BINARY|
#endif
    O_WRONLY|O_EXCL|O_CREAT;

#define append_str2(p, str, len) ((char *)memcpy((p), str, (len))+(len))
#define append_str(p, str) append_str2(p, str, sizeof(str)-1)
#define append_lit(p, str) append_str2(p, str, rb_strlen_lit(str))

// The function producing the pre-compiled header.
static void
make_pch(void)
{
    const char *rest_args[] = {
# ifdef __clang__
        "-emit-pch",
        "-c",
# endif
        // -nodefaultlibs is a linker flag, but it may affect cc1 behavior on Gentoo, which should NOT be changed on pch:
        // https://gitweb.gentoo.org/proj/gcc-patches.git/tree/7.3.0/gentoo/13_all_default-ssp-fix.patch
        GCC_NOSTDLIB_FLAGS
        "-o", pch_file, header_file,
        NULL,
    };

    verbose(2, "Creating precompiled header");
    char **args = form_args(4, cc_common_args, CC_CODEFLAG_ARGS, cc_added_args, rest_args);
    if (args == NULL) {
        mjit_warning("making precompiled header failed on forming args");
        pch_status = PCH_FAILED;
        return;
    }

    int exit_code = exec_process(cc_path, args);
    free(args);

    if (exit_code == 0) {
        pch_status = PCH_SUCCESS;
    }
    else {
        mjit_warning("Making precompiled header failed on compilation. Stopping MJIT worker...");
        pch_status = PCH_FAILED;
    }
}

static int
c_compile(const char *c_file, const char *so_file)
{
    const char *so_args[] = {
        "-o", so_file,
# ifdef __clang__
        "-include-pch", pch_file,
# endif
        c_file, NULL
    };

# if defined(__MACH__)
    extern VALUE rb_libruby_selfpath;
    const char *loader_args[] = {"-bundle_loader", StringValuePtr(rb_libruby_selfpath), NULL};
# else
    const char *loader_args[] = {NULL};
# endif

    char **args = form_args(8, CC_LDSHARED_ARGS, CC_CODEFLAG_ARGS, cc_added_args,
                            so_args, loader_args, CC_LIBS, CC_DLDFLAGS_ARGS, CC_LINKER_ARGS);
    if (args == NULL) return 1;

    int exit_code = exec_process(cc_path, args);
    if (!mjit_opts.save_temps)
        remove_file(c_file);

    free(args);
    return exit_code;
}

static int
c_compile_unit(struct rb_mjit_unit *unit)
{
    static const char c_ext[] = ".c";
    static const char so_ext[] = DLEXT;
    char c_file[MAXPATHLEN], so_file[MAXPATHLEN];

    sprint_uniq_filename(c_file, (int)sizeof(c_file), unit->id, MJIT_TMP_PREFIX, c_ext);
    sprint_uniq_filename(so_file, (int)sizeof(so_file), unit->id, MJIT_TMP_PREFIX, so_ext);

    return c_compile(c_file, so_file);
}

static void compile_prelude(FILE *f);

// Compile all JIT code into a single .c file
static bool
mjit_compact(char* c_file)
{
    FILE *f;
    int fd = rb_cloexec_open(c_file, c_file_access_mode, 0600);
    if (fd < 0 || (f = fdopen(fd, "w")) == NULL) {
        int e = errno;
        if (fd >= 0) (void)close(fd);
        verbose(1, "Failed to fopen '%s', giving up JIT for it (%s)", c_file, strerror(e));
        return false;
    }

    compile_prelude(f);

    // This entire loop lock GC so that we do not need to consider a case that
    // ISeq is GC-ed in a middle of re-compilation. It takes 3~4ms with 100 methods
    // on my machine. It's not too bad compared to compilation time of C (7200~8000ms),
    // but it might be larger if we use a larger --jit-max-cache.
    //
    // TODO: Consider using a more granular lock after we implement inlining across
    // compacted functions (not done yet).
    bool success = true;
    struct rb_mjit_unit *child_unit = 0;
    ccan_list_for_each(&active_units.head, child_unit, unode) {
        if (!success) continue;
        if (ISEQ_BODY(child_unit->iseq)->jit_unit == NULL) continue; // Sometimes such units are created. TODO: Investigate why

        char funcname[MAXPATHLEN];
        sprint_funcname(funcname, sizeof(funcname), child_unit);

        int iseq_lineno = ISEQ_BODY(child_unit->iseq)->location.first_lineno;
        const char *sep = "@";
        const char *iseq_label = RSTRING_PTR(ISEQ_BODY(child_unit->iseq)->location.label);
        const char *iseq_path = RSTRING_PTR(rb_iseq_path(child_unit->iseq));
        if (!iseq_label) iseq_label = sep = "";
        fprintf(f, "\n/* %s%s%s:%d */\n", iseq_label, sep, iseq_path, iseq_lineno);
        success &= mjit_compile(f, child_unit->iseq, funcname, child_unit->id);
    }

    fclose(f);
    return success;
}

// Compile all cached .c files and build a single .so file. Reload all JIT func from it.
// This improves the code locality for better performance in terms of iTLB and iCache.
static bool
mjit_compact_unit(struct rb_mjit_unit *unit)
{
    static const char c_ext[] = ".c";
    static const char so_ext[] = DLEXT;
    char c_file[MAXPATHLEN], so_file[MAXPATHLEN];

    sprint_uniq_filename(c_file, (int)sizeof(c_file), unit->id, MJIT_TMP_PREFIX, c_ext);
    sprint_uniq_filename(so_file, (int)sizeof(so_file), unit->id, MJIT_TMP_PREFIX, so_ext);

    return mjit_compact(c_file);
}

static void
load_compact_funcs_from_so(struct rb_mjit_unit *unit, char *c_file, char *so_file)
{
    struct rb_mjit_unit *cur = 0;
    double end_time = real_ms_time();

    void *handle = dlopen(so_file, RTLD_NOW);
    if (handle == NULL) {
        mjit_warning("failure in loading code from compacted '%s': %s", so_file, dlerror());
        free(unit);
        return;
    }
    unit->handle = handle;

    // lazily dlclose handle (and .so file for win32) on `mjit_finish()`.
    add_to_list(unit, &compact_units);

    if (!mjit_opts.save_temps)
        remove_so_file(so_file, unit);

    ccan_list_for_each(&active_units.head, cur, unode) {
        void *func;
        char funcname[MAXPATHLEN];
        sprint_funcname(funcname, sizeof(funcname), cur);

        if ((func = dlsym(handle, funcname)) == NULL) {
            mjit_warning("skipping to reload '%s' from '%s': %s", funcname, so_file, dlerror());
            continue;
        }

        if (cur->iseq) { // Check whether GCed or not
            // Usage of jit_code might be not in a critical section.
            MJIT_ATOMIC_SET(ISEQ_BODY(cur->iseq)->jit_func, (jit_func_t)func);
        }
    }
    verbose(1, "JIT compaction (%.1fms): Compacted %d methods %s -> %s", end_time - current_cc_ms, active_units.length, c_file, so_file);
}

static void *
load_func_from_so(const char *so_file, const char *funcname, struct rb_mjit_unit *unit)
{
    void *handle, *func;

    handle = dlopen(so_file, RTLD_NOW);
    if (handle == NULL) {
        mjit_warning("failure in loading code from '%s': %s", so_file, dlerror());
        return (void *)NOT_COMPILED_JIT_ISEQ_FUNC;
    }

    func = dlsym(handle, funcname);
    unit->handle = handle;
    return func;
}

#ifndef __clang__
static const char *
header_name_end(const char *s)
{
    const char *e = s + strlen(s);
# ifdef __GNUC__ // don't chomp .pch for mswin
    static const char suffix[] = ".gch";

    // chomp .gch suffix
    if (e > s+sizeof(suffix)-1 && strcmp(e-sizeof(suffix)+1, suffix) == 0) {
        e -= sizeof(suffix)-1;
    }
# endif
    return e;
}
#endif

// Print platform-specific prerequisites in generated code.
static void
compile_prelude(FILE *f)
{
#ifndef __clang__ // -include-pch is used for Clang
    const char *s = pch_file;
    const char *e = header_name_end(s);

    fprintf(f, "#include \"");
    // print pch_file except .gch for gcc, but keep .pch for mswin
    for (; s < e; s++) {
        switch (*s) {
          case '\\': case '"':
            fputc('\\', f);
        }
        fputc(*s, f);
    }
    fprintf(f, "\"\n");
#endif
}

// Compile ISeq in UNIT and return function pointer of JIT-ed code.
// It may return NOT_COMPILED_JIT_ISEQ_FUNC if something went wrong.
static bool
mjit_compile_unit(struct rb_mjit_unit *unit)
{
    static const char c_ext[] = ".c";
    static const char so_ext[] = DLEXT;
    char c_file[MAXPATHLEN], so_file[MAXPATHLEN], funcname[MAXPATHLEN];

    sprint_uniq_filename(c_file, (int)sizeof(c_file), unit->id, MJIT_TMP_PREFIX, c_ext);
    sprint_uniq_filename(so_file, (int)sizeof(so_file), unit->id, MJIT_TMP_PREFIX, so_ext);
    sprint_funcname(funcname, sizeof(funcname), unit);

    FILE *f;
    int fd = rb_cloexec_open(c_file, c_file_access_mode, 0600);
    if (fd < 0 || (f = fdopen(fd, "w")) == NULL) {
        int e = errno;
        if (fd >= 0) (void)close(fd);
        verbose(1, "Failed to fopen '%s', giving up JIT for it (%s)", c_file, strerror(e));
        return false;
    }

    // print #include of MJIT header, etc.
    compile_prelude(f);

    // To make MJIT worker thread-safe against GC.compact, copy ISeq values while `in_jit` is true.
    int iseq_lineno = ISEQ_BODY(unit->iseq)->location.first_lineno;
    char *iseq_label = alloca(RSTRING_LEN(ISEQ_BODY(unit->iseq)->location.label) + 1);
    char *iseq_path  = alloca(RSTRING_LEN(rb_iseq_path(unit->iseq)) + 1);
    strcpy(iseq_label, RSTRING_PTR(ISEQ_BODY(unit->iseq)->location.label));
    strcpy(iseq_path,  RSTRING_PTR(rb_iseq_path(unit->iseq)));

    verbose(2, "start compilation: %s@%s:%d -> %s", iseq_label, iseq_path, iseq_lineno, c_file);
    fprintf(f, "/* %s@%s:%d */\n\n", iseq_label, iseq_path, iseq_lineno);
    bool success = mjit_compile(f, unit->iseq, funcname, unit->id);

    fclose(f);
    if (!success) {
        if (!mjit_opts.save_temps)
            remove_file(c_file);
        verbose(1, "JIT failure: %s@%s:%d -> %s", iseq_label, iseq_path, iseq_lineno, c_file);
    }
    return success;
}

static pid_t
start_c_compile_unit(struct rb_mjit_unit *unit)
{
    extern pid_t rb_mjit_fork();
    pid_t pid = rb_mjit_fork();
    if (pid == 0) {
        int exit_code = c_compile_unit(unit);
        exit(exit_code);
    }
    else {
        return pid;
    }
}

// Capture cc entries of `captured_iseq` and append them to `compiled_iseq->jit_unit->cc_entries`.
// This is needed when `captured_iseq` is inlined by `compiled_iseq` and GC needs to mark inlined cc.
//
// Index to refer to `compiled_iseq->jit_unit->cc_entries` is returned instead of the address
// because old addresses may be invalidated by `realloc` later. -1 is returned on failure.
//
// This assumes that it's safe to reference cc without acquiring GVL.
int
mjit_capture_cc_entries(const struct rb_iseq_constant_body *compiled_iseq, const struct rb_iseq_constant_body *captured_iseq)
{
    VM_ASSERT(compiled_iseq != NULL);
    VM_ASSERT(compiled_iseq->jit_unit != NULL);
    VM_ASSERT(captured_iseq != NULL);

    struct rb_mjit_unit *unit = compiled_iseq->jit_unit;
    unsigned int new_entries_size = unit->cc_entries_size + captured_iseq->ci_size;
    VM_ASSERT(captured_iseq->ci_size > 0);

    // Allocate new cc_entries and append them to unit->cc_entries
    const struct rb_callcache **cc_entries;
    int cc_entries_index = unit->cc_entries_size;
    if (unit->cc_entries_size == 0) {
        VM_ASSERT(unit->cc_entries == NULL);
        unit->cc_entries = cc_entries = malloc(sizeof(struct rb_callcache *) * new_entries_size);
        if (cc_entries == NULL) return -1;
    }
    else {
        void *cc_ptr = (void *)unit->cc_entries; // get rid of bogus warning by VC
        cc_entries = realloc(cc_ptr, sizeof(struct rb_callcache *) * new_entries_size);
        if (cc_entries == NULL) return -1;
        unit->cc_entries = cc_entries;
        cc_entries += cc_entries_index;
    }
    unit->cc_entries_size = new_entries_size;

    // Capture cc to cc_enties
    for (unsigned int i = 0; i < captured_iseq->ci_size; i++) {
        cc_entries[i] = captured_iseq->call_data[i].cc;
    }

    return cc_entries_index;
}

// Set up field `used_code_p` for unit iseqs whose iseq on the stack of ec.
static void
mark_iseq_units(const rb_iseq_t *iseq, void *data)
{
    if (ISEQ_BODY(iseq)->jit_unit != NULL) {
        ISEQ_BODY(iseq)->jit_unit->used_code_p = true;
    }
}

// Unload JIT code of some units to satisfy the maximum permitted
// number of units with a loaded code.
static void
unload_units(void)
{
    struct rb_mjit_unit *unit = 0, *next;
    int units_num = active_units.length;

    // For now, we don't unload units when ISeq is GCed. We should
    // unload such ISeqs first here.
    ccan_list_for_each_safe(&active_units.head, unit, next, unode) {
        if (unit->iseq == NULL) { // ISeq is GCed.
            remove_from_list(unit, &active_units);
            free_unit(unit);
        }
    }

    // Detect units which are in use and can't be unloaded.
    ccan_list_for_each(&active_units.head, unit, unode) {
        VM_ASSERT(unit->iseq != NULL && unit->handle != NULL);
        unit->used_code_p = false;
    }
    // All threads have a root_fiber which has a mjit_cont. Other normal fibers also
    // have a mjit_cont. Thus we can check ISeqs in use by scanning ec of mjit_conts.
    rb_jit_cont_each_iseq(mark_iseq_units, NULL);
    // TODO: check stale_units and unload unused ones! (note that the unit is not associated to ISeq anymore)

    // Unload units whose total_calls is smaller than any total_calls in unit_queue.
    // TODO: make the algorithm more efficient
    long unsigned prev_queue_calls = -1;
    while (true) {
        // Calculate the next max total_calls in unit_queue
        long unsigned max_queue_calls = 0;
        ccan_list_for_each(&unit_queue.head, unit, unode) {
            if (unit->iseq != NULL && max_queue_calls < ISEQ_BODY(unit->iseq)->total_calls
                    && ISEQ_BODY(unit->iseq)->total_calls < prev_queue_calls) {
                max_queue_calls = ISEQ_BODY(unit->iseq)->total_calls;
            }
        }
        prev_queue_calls = max_queue_calls;

        bool unloaded_p = false;
        ccan_list_for_each_safe(&active_units.head, unit, next, unode) {
            if (unit->used_code_p) // We can't unload code on stack.
                continue;

            if (max_queue_calls > ISEQ_BODY(unit->iseq)->total_calls) {
                verbose(2, "Unloading unit %d (calls=%lu, threshold=%lu)",
                        unit->id, ISEQ_BODY(unit->iseq)->total_calls, max_queue_calls);
                VM_ASSERT(unit->handle != NULL);
                remove_from_list(unit, &active_units);
                free_unit(unit);
                unloaded_p = true;
            }
        }
        if (!unloaded_p) break;
    }

    if (units_num > active_units.length) {
        verbose(1, "Too many JIT code -- %d units unloaded", units_num - active_units.length);
        total_unloads += units_num - active_units.length;
    }
}

static void mjit_add_iseq_to_process(const rb_iseq_t *iseq, const struct rb_mjit_compile_info *compile_info, bool worker_p);

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
            free(unit);
        }
        else {
            free_unit(unit);
        }
    }
    list->length = 0;
}

static void mjit_wait(struct rb_iseq_constant_body *body);

// Check the unit queue and start mjit_compile if nothing is in progress.
static void
check_unit_queue(void)
{
    if (mjit_opts.custom) return;
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

    // Run the MJIT compiler synchronously
    current_cc_ms = real_ms_time();
    current_cc_unit = unit;
    bool success = mjit_compile_unit(unit);
    if (!success) {
        mjit_notify_waitpid(1);
        return;
    }

    // Run the C compiler asynchronously (unless --mjit-wait)
    if (mjit_opts.wait) {
        int exit_code = c_compile_unit(unit);
        mjit_notify_waitpid(exit_code);
    }
    else {
        current_cc_pid = start_c_compile_unit(unit);
        if (current_cc_pid == -1) { // JIT failure
            current_cc_pid = 0;
            current_cc_unit->iseq->body->jit_func = (jit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC; // TODO: consider unit->compact_p
            current_cc_unit = NULL;
        }
    }
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
    }
    else { // Normal unit
        unit->iseq = (rb_iseq_t *)iseq;
        ISEQ_BODY(iseq)->jit_unit = unit;
    }
    return unit;
}

// Check if it should compact all JIT code and start it as needed
static void
check_compaction(void)
{
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
        if (unit == NULL) return;

        // Run the MJIT compiler synchronously
        current_cc_ms = real_ms_time();
        current_cc_unit = unit;
        bool success = mjit_compact_unit(unit);
        if (!success) {
            mjit_notify_waitpid(1);
            return;
        }

        // Run the C compiler asynchronously (unless --mjit-wait)
        if (mjit_opts.wait) {
            int exit_code = c_compile_unit(unit);
            mjit_notify_waitpid(exit_code);
        }
        else {
            current_cc_pid = start_c_compile_unit(unit);
            // TODO: check -1
        }
    }
}

// Check the current CC process if any, and start a next C compiler process as needed.
void
mjit_notify_waitpid(int exit_code)
{
    // TODO: check current_cc_pid?
    current_cc_pid = 0;

    // Delete .c file
    char c_file[MAXPATHLEN];
    sprint_uniq_filename(c_file, (int)sizeof(c_file), current_cc_unit->id, MJIT_TMP_PREFIX, ".c");

    // Check the result
    if (exit_code != 0) {
        verbose(2, "Failed to generate so");
        if (!current_cc_unit->compact_p) {
            current_cc_unit->iseq->body->jit_func = (jit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
        }
        free_unit(current_cc_unit);
        current_cc_unit = NULL;
        return;
    }

    // Load .so file
    char so_file[MAXPATHLEN];
    sprint_uniq_filename(so_file, (int)sizeof(so_file), current_cc_unit->id, MJIT_TMP_PREFIX, DLEXT);
    if (current_cc_unit->compact_p) { // Compact unit
        load_compact_funcs_from_so(current_cc_unit, c_file, so_file);
        current_cc_unit = NULL;
    }
    else { // Normal unit
        // Load the function from so
        char funcname[MAXPATHLEN];
        sprint_funcname(funcname, sizeof(funcname), current_cc_unit);
        void *func = load_func_from_so(so_file, funcname, current_cc_unit);

        // Delete .so file
        if (!mjit_opts.save_temps)
            remove_file(so_file);

        // Set the jit_func if successful
        if (current_cc_unit->iseq != NULL) { // mjit_free_iseq could nullify this
            rb_iseq_t *iseq = current_cc_unit->iseq;
            if ((uintptr_t)func > (uintptr_t)LAST_JIT_ISEQ_FUNC) {
                double end_time = real_ms_time();
                verbose(1, "JIT success (%.1fms): %s@%s:%d -> %s",
                        end_time - current_cc_ms, RSTRING_PTR(ISEQ_BODY(iseq)->location.label),
                        RSTRING_PTR(rb_iseq_path(iseq)), ISEQ_BODY(iseq)->location.first_lineno, c_file);

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
        && strcmp("<internal:mjit>", RSTRING_PTR(rb_iseq_path(iseq))) != 0;
}

// RubyVM::MJIT
static VALUE rb_mMJIT = 0;
// RubyVM::MJIT::C
static VALUE rb_mMJITC = 0;
// RubyVM::MJIT::Compiler
static VALUE rb_cMJITCompiler = 0;
// RubyVM::MJIT::CPointer::Struct_rb_iseq_t
static VALUE rb_cMJITIseqPtr = 0;

// [experimental] Call custom RubyVM::MJIT.compile if defined
static void
mjit_hook_custom_compile(const rb_iseq_t *iseq)
{
    bool original_call_p = mjit_call_p;
    mjit_call_p = false; // Avoid impacting JIT metrics by itself

    VALUE iseq_class = rb_funcall(rb_mMJITC, rb_intern("rb_iseq_t"), 0);
    VALUE iseq_ptr = rb_funcall(iseq_class, rb_intern("new"), 1, ULONG2NUM((size_t)iseq));
    VALUE jit_func = rb_funcall(rb_mMJIT, rb_intern("compile"), 1, iseq_ptr);
    ISEQ_BODY(iseq)->jit_func = (jit_func_t)NUM2ULONG(jit_func);

    mjit_call_p = original_call_p;
}

// If recompile_p is true, the call is initiated by mjit_recompile.
// This assumes the caller holds CRITICAL_SECTION when recompile_p is true.
static void
mjit_add_iseq_to_process(const rb_iseq_t *iseq, const struct rb_mjit_compile_info *compile_info, bool recompile_p)
{
    if (!mjit_enabled || pch_status != PCH_SUCCESS || !rb_ractor_main_p()) // TODO: Support non-main Ractors
        return;
    if (mjit_opts.custom) {
        mjit_hook_custom_compile(iseq);
        return;
    }
    if (!mjit_target_iseq_p(iseq)) {
        ISEQ_BODY(iseq)->jit_func = (jit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC; // skip mjit_wait
        return;
    }

    RB_DEBUG_COUNTER_INC(mjit_add_iseq_to_process);
    ISEQ_BODY(iseq)->jit_func = (jit_func_t)NOT_READY_JIT_ISEQ_FUNC;
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

// For this timeout seconds, mjit_finish will wait for JIT compilation finish.
#define MJIT_WAIT_TIMEOUT_SECONDS 5

static void
mjit_wait(struct rb_iseq_constant_body *body)
{
    pid_t initial_pid = current_cc_pid;
    if (initial_pid == 0) {
        mjit_warning("initial_pid was 0 on mjit_wait");
        return;
    }

    int tries = 0;
    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = 1000;
    while (body == NULL ? current_cc_pid == initial_pid : body->jit_func == (jit_func_t)NOT_READY_JIT_ISEQ_FUNC) { // TODO: refactor this
        tries++;
        if (tries / 1000 > MJIT_WAIT_TIMEOUT_SECONDS || pch_status == PCH_FAILED) {
            if (body != NULL) {
                body->jit_func = (jit_func_t) NOT_COMPILED_JIT_ISEQ_FUNC; // JIT worker seems dead. Give up.
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
    VM_ASSERT(body->jit_unit != NULL);
    return &body->jit_unit->compile_info;
}

static void
mjit_recompile(const rb_iseq_t *iseq)
{
    if ((uintptr_t)ISEQ_BODY(iseq)->jit_func <= (uintptr_t)LAST_JIT_ISEQ_FUNC)
        return;

    verbose(1, "JIT recompile: %s@%s:%d", RSTRING_PTR(ISEQ_BODY(iseq)->location.label),
            RSTRING_PTR(rb_iseq_path(iseq)), ISEQ_BODY(iseq)->location.first_lineno);
    VM_ASSERT(ISEQ_BODY(iseq)->jit_unit != NULL);

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

    return true;
}

static char *
system_default_tmpdir(void)
{
    // c.f. ext/etc/etc.c:etc_systmpdir()
#if defined _CS_DARWIN_USER_TEMP_DIR
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
#ifndef S_IWOTH
#   define S_IWOTH 002
#endif
    if (st.st_mode & S_IWOTH) {
#ifdef S_ISVTX
        if (!(st.st_mode & S_ISVTX)) return FALSE;
#else
        return FALSE;
#endif
    }
    if (access(dir, W_OK)) return FALSE;
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
#define DEFAULT_CALL_THRESHOLD 10000

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
        mjit_opt->warnings = true;
    }
    else if (opt_match(s, l, "debug")) {
        if (*s)
            mjit_opt->debug_flags = strdup(s + 1);
        else
            mjit_opt->debug = true;
    }
    else if (opt_match_noarg(s, l, "wait")) {
        mjit_opt->wait = true;
    }
    else if (opt_match_noarg(s, l, "save-temps")) {
        mjit_opt->save_temps = true;
    }
    else if (opt_match(s, l, "verbose")) {
        mjit_opt->verbose = *s ? atoi(s + 1) : 1;
    }
    else if (opt_match_arg(s, l, "max-cache")) {
        mjit_opt->max_cache_size = atoi(s + 1);
    }
    else if (opt_match_arg(s, l, "call-threshold")) {
        mjit_opt->call_threshold = atoi(s + 1);
    }
    // --mjit=pause is an undocumented feature for experiments
    else if (opt_match_noarg(s, l, "pause")) {
        mjit_opt->pause = true;
    }
    else {
        rb_raise(rb_eRuntimeError,
                 "invalid MJIT option `%s' (--help will show valid MJIT options)", s);
    }
}

#define M(shortopt, longopt, desc) RUBY_OPT_MESSAGE(shortopt, longopt, desc)
const struct ruby_opt_message mjit_option_messages[] = {
    M("--mjit-warnings",           "", "Enable printing JIT warnings"),
    M("--mjit-debug",              "", "Enable JIT debugging (very slow), or add cflags if specified"),
    M("--mjit-wait",               "", "Wait until JIT compilation finishes every time (for testing)"),
    M("--mjit-save-temps",         "", "Save JIT temporary files in $TMP or /tmp (for testing)"),
    M("--mjit-verbose=num",        "", "Print JIT logs of level num or less to stderr (default: 0)"),
    M("--mjit-max-cache=num",      "", "Max number of methods to be JIT-ed in a cache (default: "
      STRINGIZE(DEFAULT_MAX_CACHE_SIZE) ")"),
    M("--mjit-call-threshold=num", "", "Number of calls to trigger JIT (for testing, default: "
      STRINGIZE(DEFAULT_CALL_THRESHOLD) ")"),
    {0}
};
#undef M

// Initialize MJIT.  Start a thread creating the precompiled header and
// processing ISeqs.  The function should be called first for using MJIT.
// If everything is successful, MJIT_INIT_P will be TRUE.
void
mjit_init(const struct mjit_options *opts)
{
    VM_ASSERT(mjit_enabled);
    mjit_opts = *opts;

    // MJIT doesn't support miniruby, but it might reach here by MJIT_FORCE_ENABLE.
    rb_mMJIT = rb_const_get(rb_cRubyVM, rb_intern("MJIT"));
    if (!rb_const_defined(rb_mMJIT, rb_intern("Compiler"))) {
        verbose(1, "Disabling MJIT because RubyVM::MJIT::Compiler is not defined");
        mjit_enabled = false;
        return;
    }
    rb_mMJITC = rb_const_get(rb_mMJIT, rb_intern("C"));
    rb_cMJITCompiler = rb_funcall(rb_const_get(rb_mMJIT, rb_intern("Compiler")), rb_intern("new"), 0);
    rb_cMJITIseqPtr = rb_funcall(rb_mMJITC, rb_intern("rb_iseq_t"), 0);
    rb_gc_register_mark_object(rb_cMJITCompiler);
    rb_gc_register_mark_object(rb_cMJITIseqPtr);

    mjit_call_p = true;
    mjit_pid = getpid();

    // Normalize options
    if (mjit_opts.call_threshold == 0)
        mjit_opts.call_threshold = DEFAULT_CALL_THRESHOLD;
    if (mjit_opts.max_cache_size <= 0)
        mjit_opts.max_cache_size = DEFAULT_MAX_CACHE_SIZE;
    if (mjit_opts.max_cache_size < MIN_CACHE_SIZE)
        mjit_opts.max_cache_size = MIN_CACHE_SIZE;

    // Initialize variables for compilation
    pch_status = PCH_NOT_READY;
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

    // If --mjit=pause is given, lazily start MJIT when RubyVM::MJIT.resume is called.
    // You can use it to control MJIT warmup, or to customize the JIT implementation.
    if (!mjit_opts.pause) {
        // TODO: Consider running C compiler asynchronously
        make_pch();

        // Enable MJIT compilation
        start_worker();
    }
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

    // Lazily prepare PCH when --mjit=pause is given
    if (pch_status == PCH_NOT_READY) {
        if (rb_respond_to(rb_mMJIT, rb_intern("compile"))) {
            // [experimental] defining RubyVM::MJIT.compile allows you to replace JIT
            mjit_opts.custom = true;
            pch_status = PCH_SUCCESS;
        }
        else {
            // Lazy MJIT boot
            make_pch();
        }
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
                RSTRING_PTR(rb_iseq_path(iseq)), ISEQ_BODY(iseq)->location.first_lineno);
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

    if (!mjit_opts.save_temps && getpid() == pch_owner_pid && pch_status == PCH_SUCCESS && !mjit_opts.custom)
        remove_file(pch_file);

    xfree(header_file); header_file = NULL;
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

// Compile ISeq to C code in `f`. It returns true if it succeeds to compile.
bool
mjit_compile(FILE *f, const rb_iseq_t *iseq, const char *funcname, int id)
{
    bool original_call_p = mjit_call_p;
    mjit_call_p = false; // Avoid impacting JIT metrics by itself

    VALUE iseq_ptr = rb_funcall(rb_cMJITIseqPtr, rb_intern("new"), 1, ULONG2NUM((size_t)iseq));
    VALUE src = rb_funcall(rb_cMJITCompiler, rb_intern("compile"), 3,
                           iseq_ptr, rb_str_new_cstr(funcname), INT2NUM(id));
    if (!NIL_P(src)) {
        fprintf(f, "%s", RSTRING_PTR(src));
    }

    mjit_call_p = original_call_p;
    return !NIL_P(src);
}

#include "mjit.rbinc"

#endif // USE_MJIT
