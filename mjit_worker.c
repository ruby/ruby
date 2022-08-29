/**********************************************************************

  mjit_worker.c - Worker for MRI method JIT compiler

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.

**********************************************************************/

// NOTE: All functions in this file are executed on MJIT worker. So don't
// call Ruby methods (C functions that may call rb_funcall) or trigger
// GC (using ZALLOC, xmalloc, xfree, etc.) in this file.

/* However, note that calling `free` for resources `xmalloc`-ed in mjit.c,
   which is currently done in some places, is sometimes problematic in the
   following situations:

   * malloc library could be different between interpreter and extensions
     on Windows (perhaps not applicable to MJIT because CC is the same)
   * xmalloc -> free leaks extra space used for USE_GC_MALLOC_OBJ_INFO_DETAILS
     (not enabled by default)

   ...in short, it's usually not a problem in MJIT. But maybe it's worth
   fixing for consistency or for USE_GC_MALLOC_OBJ_INFO_DETAILS support.
*/

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

#ifdef __sun
#define __EXTENSIONS__ 1
#endif

#include "vm_core.h"
#include "vm_callinfo.h"
#include "mjit.h"
#include "gc.h"
#include "ruby_assert.h"
#include "ruby/debug.h"
#include "ruby/thread.h"
#include "ruby/version.h"
#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"
#include "internal/compile.h"

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
#else
#include <sys/wait.h>
#include <sys/time.h>
#include <dlfcn.h>
#endif
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

#ifdef _WIN32
#define dlopen(name,flag) ((void*)LoadLibrary(name))
#define dlerror() strerror(rb_w32_map_errno(GetLastError()))
#define dlsym(handle,name) ((void*)GetProcAddress((handle),(name)))
#define dlclose(handle) (!FreeLibrary(handle))
#define RTLD_NOW  -1

#define waitpid(pid,stat_loc,options) (WaitForSingleObject((HANDLE)(pid), INFINITE), GetExitCodeProcess((HANDLE)(pid), (LPDWORD)(stat_loc)), CloseHandle((HANDLE)pid), (pid))
#define WIFEXITED(S) ((S) != STILL_ACTIVE)
#define WEXITSTATUS(S) (S)
#define WIFSIGNALED(S) (0)
typedef intptr_t pid_t;
#endif

// Atomically set function pointer if possible.
#define MJIT_ATOMIC_SET(var, val) (void)ATOMIC_PTR_EXCHANGE(var, val)

#define MJIT_TMP_PREFIX "_ruby_mjit_"

// JIT compaction requires the header transformation because linking multiple .o files
// doesn't work without having `static` in the same function definitions. We currently
// don't support transforming the MJIT header on Windows.
#ifdef _WIN32
# define USE_JIT_COMPACTION 0
#else
# define USE_JIT_COMPACTION 1
#endif

// The unit structure that holds metadata of ISeq for MJIT.
struct rb_mjit_unit {
    struct list_node unode;
    // Unique order number of unit.
    int id;
    // Dlopen handle of the loaded object file.
    void *handle;
    rb_iseq_t *iseq;
#if defined(_WIN32)
    // DLL cannot be removed while loaded on Windows. If this is set, it'll be lazily deleted.
    char *so_file;
#endif
    // Only used by unload_units. Flag to check this unit is currently on stack or not.
    bool used_code_p;
    // True if this is still in active_units but it's to be lazily removed
    bool stale_p;
    // mjit_compile's optimization switches
    struct rb_mjit_compile_info compile_info;
    // captured CC values, they should be marked with iseq.
    const struct rb_callcache **cc_entries;
    unsigned int cc_entries_size; // iseq->body->ci_size + ones of inlined iseqs
};

// Linked list of struct rb_mjit_unit.
struct rb_mjit_unit_list {
    struct list_head head;
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
extern rb_pid_t ruby_waitpid_locked(rb_vm_t *, rb_pid_t, int *status, int options, rb_nativethread_cond_t *cond);

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
static struct rb_mjit_unit_list unit_queue = { LIST_HEAD_INIT(unit_queue.head) };
// List of units which are successfully compiled.
static struct rb_mjit_unit_list active_units = { LIST_HEAD_INIT(active_units.head) };
// List of compacted so files which will be cleaned up by `free_list()` in `mjit_finish()`.
static struct rb_mjit_unit_list compact_units = { LIST_HEAD_INIT(compact_units.head) };
// List of units before recompilation and just waiting for dlclose().
static struct rb_mjit_unit_list stale_units = { LIST_HEAD_INIT(stale_units.head) };
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
// Greater than 0 when GC is working.
static int in_gc = 0;
// True when JIT is working.
static bool in_jit = false;
// True when active_units has at least one stale_p=true unit.
static bool pending_stale_p = false;
// The times when unload_units is requested. unload_units is called after some requests.
static int unload_requests = 0;
// The total number of unloaded units.
static int total_unloads = 0;
// Set to true to stop worker.
static bool stop_worker_p;
// Set to true if worker is stopped.
static bool worker_stopped;

// Path of "/tmp", which can be changed to $TMP in MinGW.
static char *tmp_dir;
// Hash like { 1 => true, 2 => true, ... } whose keys are valid `class_serial`s.
// This is used to invalidate obsoleted CALL_CACHE.
static VALUE valid_class_serials;

// Used C compiler path.
static const char *cc_path;
// Used C compiler flags.
static const char **cc_common_args;
// Used C compiler flags added by --jit-debug=...
static char **cc_added_args;
// Name of the precompiled header file.
static char *pch_file;
// The process id which should delete the pch_file on mjit_finish.
static rb_pid_t pch_owner_pid;
// Status of the precompiled header creation.  The status is
// shared by the workers and the pch thread.
static enum {PCH_NOT_READY, PCH_FAILED, PCH_SUCCESS} pch_status;

#ifndef _MSC_VER
// Name of the header file.
static char *header_file;
#endif

#ifdef _WIN32
// Linker option to enable libruby.
static char *libruby_pathflag;
#endif

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

// Use `-nodefaultlibs -nostdlib` for GCC where possible, which does not work on mingw, cygwin, AIX, and OpenBSD.
// This seems to improve MJIT performance on GCC.
#if defined __GNUC__ && !defined __clang__ && !defined(_WIN32) && !defined(__CYGWIN__) && !defined(_AIX) && !defined(__OpenBSD__)
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

static const char *const CC_LDSHARED_ARGS[] = {MJIT_LDSHARED GCC_PIC_FLAGS NULL};
static const char *const CC_DLDFLAGS_ARGS[] = {MJIT_DLDFLAGS NULL};
// `CC_LINKER_ARGS` are linker flags which must be passed to `-c` as well.
static const char *const CC_LINKER_ARGS[] = {
#if defined __GNUC__ && !defined __clang__ && !defined(__OpenBSD__)
    "-nostartfiles",
#endif
    GCC_NOSTDLIB_FLAGS NULL
};

static const char *const CC_LIBS[] = {
#if defined(_WIN32) || defined(__CYGWIN__)
    MJIT_LIBS // mswin, mingw, cygwin
#endif
#if defined __GNUC__ && !defined __clang__
# if defined(_WIN32)
    "-lmsvcrt", // mingw
# endif
    "-lgcc", // mingw, cygwin, and GCC platforms using `-nodefaultlibs -nostdlib`
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

    list_add_tail(&list->head, &unit->unode);
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

    list_del(&unit->unode);
    list->length--;
}

static void
remove_file(const char *filename)
{
    if (remove(filename)) {
        mjit_warning("failed to remove \"%s\": %s", filename, strerror(errno));
    }
}

// Lazily delete .so files.
static void
clean_temp_files(struct rb_mjit_unit *unit)
{
#if defined(_WIN32)
    if (unit->so_file) {
        char *so_file = unit->so_file;

        unit->so_file = NULL;
        // unit->so_file is set only when mjit_opts.save_temps is false.
        remove_file(so_file);
        free(so_file);
    }
#endif
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
        unit->iseq->body->jit_func = (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
        unit->iseq->body->jit_unit = NULL;
    }
    if (unit->cc_entries) {
        void *entries = (void *)unit->cc_entries;
        free(entries);
    }
    if (unit->handle && dlclose(unit->handle)) { // handle is NULL if it's in queue
        mjit_warning("failed to close handle for u%d: %s", unit->id, dlerror());
    }
    clean_temp_files(unit);
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

static int
sprint_uniq_filename(char *str, size_t size, unsigned long id, const char *prefix, const char *suffix)
{
    return snprintf(str, size, "%s/%sp%"PRI_PIDT_PREFIX"uu%lu%s", tmp_dir, prefix, getpid(), id, suffix);
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

// Return true if class_serial is not obsoleted. This is used by mjit_compile.c.
bool
mjit_valid_class_serial_p(rb_serial_t class_serial)
{
    CRITICAL_SECTION_START(3, "in valid_class_serial_p");
    bool found_p = rb_hash_stlike_lookup(valid_class_serials, LONG2FIX(class_serial), NULL);
    CRITICAL_SECTION_FINISH(3, "in valid_class_serial_p");
    return found_p;
}

// Return the best unit from list.  The best is the first
// high priority unit or the unit whose iseq has the biggest number
// of calls so far.
static struct rb_mjit_unit *
get_from_list(struct rb_mjit_unit_list *list)
{
    while (in_gc) {
        verbose(3, "Waiting wakeup from GC");
        rb_native_cond_wait(&mjit_gc_wakeup, &mjit_engine_mutex);
    }
    in_jit = true; // Lock GC

    // Find iseq with max total_calls
    struct rb_mjit_unit *unit = NULL, *next, *best = NULL;
    list_for_each_safe(&list->head, unit, next, unode) {
        if (unit->iseq == NULL) { // ISeq is GCed.
            remove_from_list(unit, list);
            free_unit(unit);
            continue;
        }

        if (best == NULL || best->iseq->body->total_calls < unit->iseq->body->total_calls) {
            best = unit;
        }
    }

    in_jit = false; // Unlock GC
    verbose(3, "Sending wakeup signal to client in a mjit-worker for GC");
    rb_native_cond_signal(&mjit_client_wakeup);

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
#ifdef _WIN32
    extern HANDLE rb_w32_start_process(const char *abspath, char *const *argv, int out_fd);
    int out_fd = 0;
    if (mjit_opts.verbose <= 1) {
        // Discard cl.exe's outputs like:
        //   _ruby_mjit_p12u3.c
        //     Creating library C:.../_ruby_mjit_p12u3.lib and object C:.../_ruby_mjit_p12u3.exp
        out_fd = dev_null;
    }

    pid = (pid_t)rb_w32_start_process(abspath, argv, out_fd);
    if (pid == 0) {
        verbose(1, "MJIT: Failed to create process: %s", dlerror());
        return -1;
    }
#else
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
#endif
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
    rb_vm_t *vm = WAITPID_USE_SIGCHLD ? GET_VM() : 0;
    rb_nativethread_cond_t cond;

    if (vm) {
        rb_native_cond_initialize(&cond);
        rb_native_mutex_lock(&vm->waitpid_lock);
    }

    pid_t pid = start_process(path, argv);
    for (;pid > 0;) {
        pid_t r = vm ? ruby_waitpid_locked(vm, pid, &stat, 0, &cond)
                     : waitpid(pid, &stat, 0);
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

    if (vm) {
        rb_native_mutex_unlock(&vm->waitpid_lock);
        rb_native_cond_destroy(&cond);
    }
    return exit_code;
}

static void
remove_so_file(const char *so_file, struct rb_mjit_unit *unit)
{
#if defined(_WIN32)
    // Windows can't remove files while it's used.
    unit->so_file = strdup(so_file); // lazily delete on `clean_temp_files()`
    if (unit->so_file == NULL)
        mjit_warning("failed to allocate memory to lazily remove '%s': %s", so_file, strerror(errno));
#else
    remove_file(so_file);
#endif
}

// Print _mjitX, but make a human-readable funcname when --jit-debug is used
static void
sprint_funcname(char *funcname, const struct rb_mjit_unit *unit)
{
    const rb_iseq_t *iseq = unit->iseq;
    if (iseq == NULL || (!mjit_opts.debug && !mjit_opts.debug_flags)) {
        sprintf(funcname, "_mjit%d", unit->id);
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
    const char *method = RSTRING_PTR(iseq->body->location.label);
    if (!strcmp(method, "[]")) method = "AREF";
    if (!strcmp(method, "[]=")) method = "ASET";

    // Print and normalize
    sprintf(funcname, "_mjit%d_%s_%s", unit->id, path, method);
    for (size_t i = 0; i < strlen(funcname); i++) {
        char c = funcname[i];
        if (!(('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || ('0' <= c && c <= '9') || c == '_')) {
            funcname[i] = '_';
        }
    }
}

static const rb_iseq_t **compiling_iseqs = NULL;

static bool
set_compiling_iseqs(const rb_iseq_t *iseq)
{
    compiling_iseqs = calloc(iseq->body->iseq_size + 2, sizeof(rb_iseq_t *)); // 2: 1 (unit->iseq) + 1 (NULL end)
    if (compiling_iseqs == NULL)
        return false;

    compiling_iseqs[0] = iseq;
    int i = 1;

    unsigned int pos = 0;
    while (pos < iseq->body->iseq_size) {
#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
        int insn = rb_vm_insn_addr2insn((void *)iseq->body->iseq_encoded[pos]);
#else
        int insn = (int)iseq->body->iseq_encoded[pos];
#endif
        if (insn == BIN(opt_send_without_block)) {
            CALL_DATA cd = (CALL_DATA)iseq->body->iseq_encoded[pos + 1];
            extern const rb_iseq_t *rb_mjit_inlinable_iseq(const struct rb_callinfo *ci, const struct rb_callcache *cc);
            const rb_iseq_t *iseq = rb_mjit_inlinable_iseq(cd->ci, cd->cc);
            if (iseq != NULL) {
                compiling_iseqs[i] = iseq;
                i++;
            }
        }
        pos += insn_len(insn);
    }
    return true;
}

bool
rb_mjit_compiling_iseq_p(const rb_iseq_t *iseq)
{
    assert(compiling_iseqs != NULL);
    int i = 0;
    while (compiling_iseqs[i]) {
        if (compiling_iseqs[i] == iseq) return true;
        i++;
    }
    return false;
}

static const int c_file_access_mode =
#ifdef O_BINARY
    O_BINARY|
#endif
    O_WRONLY|O_EXCL|O_CREAT;

#define append_str2(p, str, len) ((char *)memcpy((p), str, (len))+(len))
#define append_str(p, str) append_str2(p, str, sizeof(str)-1)
#define append_lit(p, str) append_str2(p, str, rb_strlen_lit(str))

#ifdef _MSC_VER
// Compile C file to so. It returns true if it succeeds. (mswin)
static bool
compile_c_to_so(const char *c_file, const char *so_file)
{
    const char *files[] = { NULL, NULL, NULL, NULL, NULL, NULL, "-link", libruby_pathflag, NULL };
    char *p;

    // files[0] = "-Fe*.dll"
    files[0] = p = alloca(sizeof(char) * (rb_strlen_lit("-Fe") + strlen(so_file) + 1));
    p = append_lit(p, "-Fe");
    p = append_str2(p, so_file, strlen(so_file));
    *p = '\0';

    // files[1] = "-Fo*.obj"
    // We don't need .obj file, but it's somehow created to cwd without -Fo and we want to control the output directory.
    files[1] = p = alloca(sizeof(char) * (rb_strlen_lit("-Fo") + strlen(so_file) - rb_strlen_lit(DLEXT) + rb_strlen_lit(".obj") + 1));
    char *obj_file = p = append_lit(p, "-Fo");
    p = append_str2(p, so_file, strlen(so_file) - rb_strlen_lit(DLEXT));
    p = append_lit(p, ".obj");
    *p = '\0';

    // files[2] = "-Yu*.pch"
    files[2] = p = alloca(sizeof(char) * (rb_strlen_lit("-Yu") + strlen(pch_file) + 1));
    p = append_lit(p, "-Yu");
    p = append_str2(p, pch_file, strlen(pch_file));
    *p = '\0';

    // files[3] = "C:/.../rb_mjit_header-*.obj"
    files[3] = p = alloca(sizeof(char) * (strlen(pch_file) + 1));
    p = append_str2(p, pch_file, strlen(pch_file) - strlen(".pch"));
    p = append_lit(p, ".obj");
    *p = '\0';

    // files[4] = "-Tc*.c"
    files[4] = p = alloca(sizeof(char) * (rb_strlen_lit("-Tc") + strlen(c_file) + 1));
    p = append_lit(p, "-Tc");
    p = append_str2(p, c_file, strlen(c_file));
    *p = '\0';

    // files[5] = "-Fd*.pdb"
    files[5] = p = alloca(sizeof(char) * (rb_strlen_lit("-Fd") + strlen(pch_file) + 1));
    p = append_lit(p, "-Fd");
    p = append_str2(p, pch_file, strlen(pch_file) - rb_strlen_lit(".pch"));
    p = append_lit(p, ".pdb");
    *p = '\0';

    char **args = form_args(5, CC_LDSHARED_ARGS, CC_CODEFLAG_ARGS,
            files, CC_LIBS, CC_DLDFLAGS_ARGS);
    if (args == NULL)
        return false;

    int exit_code = exec_process(cc_path, args);
    free(args);

    if (exit_code == 0) {
        // remove never-used files (.obj, .lib, .exp, .pdb). XXX: Is there any way not to generate this?
        if (!mjit_opts.save_temps) {
            char *before_dot;
            remove_file(obj_file);

            before_dot = obj_file + strlen(obj_file) - rb_strlen_lit(".obj");
            append_lit(before_dot, ".lib"); remove_file(obj_file);
            append_lit(before_dot, ".exp"); remove_file(obj_file);
            append_lit(before_dot, ".pdb"); remove_file(obj_file);
        }
    }
    else {
        verbose(2, "compile_c_to_so: compile error: %d", exit_code);
    }
    return exit_code == 0;
}
#else // _MSC_VER

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
        CRITICAL_SECTION_START(3, "in make_pch");
        pch_status = PCH_FAILED;
        CRITICAL_SECTION_FINISH(3, "in make_pch");
        return;
    }

    int exit_code = exec_process(cc_path, args);
    free(args);

    CRITICAL_SECTION_START(3, "in make_pch");
    if (exit_code == 0) {
        pch_status = PCH_SUCCESS;
    }
    else {
        mjit_warning("Making precompiled header failed on compilation. Stopping MJIT worker...");
        pch_status = PCH_FAILED;
    }
    /* wakeup `mjit_finish` */
    rb_native_cond_broadcast(&mjit_pch_wakeup);
    CRITICAL_SECTION_FINISH(3, "in make_pch");
}

// Compile .c file to .so file. It returns true if it succeeds. (non-mswin)
// Not compiling .c to .so directly because it fails on MinGW, and this helps
// to generate no .dSYM on macOS.
static bool
compile_c_to_so(const char *c_file, const char *so_file)
{
    char* o_file = alloca(strlen(c_file) + 1);
    strcpy(o_file, c_file);
    o_file[strlen(c_file) - 1] = 'o';

    const char *o_args[] = {
        "-o", o_file, c_file,
# ifdef __clang__
        "-include-pch", pch_file,
# endif
        "-c", NULL
    };
    char **args = form_args(5, cc_common_args, CC_CODEFLAG_ARGS, cc_added_args, o_args, CC_LINKER_ARGS);
    if (args == NULL) return false;
    int exit_code = exec_process(cc_path, args);
    free(args);
    if (exit_code != 0) {
        verbose(2, "compile_c_to_so: failed to compile .c to .o: %d", exit_code);
        return false;
    }

    const char *so_args[] = {
        "-o", so_file,
# ifdef _WIN32
        libruby_pathflag,
# endif
        o_file, NULL
    };
# if defined(__MACH__)
    extern VALUE rb_libruby_selfpath;
    const char *loader_args[] = {"-bundle_loader", StringValuePtr(rb_libruby_selfpath), NULL};
# else
    const char *loader_args[] = {NULL};
# endif
    args = form_args(7, CC_LDSHARED_ARGS, CC_CODEFLAG_ARGS, so_args, loader_args, CC_LIBS, CC_DLDFLAGS_ARGS, CC_LINKER_ARGS);
    if (args == NULL) return false;
    exit_code = exec_process(cc_path, args);
    free(args);
    if (!mjit_opts.save_temps) remove_file(o_file);
    if (exit_code != 0) {
        verbose(2, "compile_c_to_so: failed to link .o to .so: %d", exit_code);
    }
    return exit_code == 0;
}
#endif // _MSC_VER

#if USE_JIT_COMPACTION
static void compile_prelude(FILE *f);

static bool
compile_compact_jit_code(char* c_file)
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

    // wait until mjit_gc_exit_hook is called
    CRITICAL_SECTION_START(3, "before mjit_compile to wait GC finish");
    while (in_gc) {
        verbose(3, "Waiting wakeup from GC");
        rb_native_cond_wait(&mjit_gc_wakeup, &mjit_engine_mutex);
    }
    // We need to check again here because we could've waited on GC above
    bool iseq_gced = false;
    struct rb_mjit_unit *child_unit = 0, *next;
    list_for_each_safe(&active_units.head, child_unit, next, unode) {
        if (child_unit->iseq == NULL) { // ISeq is GC-ed
            iseq_gced = true;
            verbose(1, "JIT compaction: A method for JIT code u%d is obsoleted. Compaction will be skipped.", child_unit->id);
            remove_from_list(child_unit, &active_units);
            free_unit(child_unit); // unload it without waiting for throttled unload_units to retry compaction quickly
        }
    }
    in_jit = !iseq_gced;
    CRITICAL_SECTION_FINISH(3, "before mjit_compile to wait GC finish");
    if (!in_jit) {
        fclose(f);
        if (!mjit_opts.save_temps)
            remove_file(c_file);
        return false;
    }

    // This entire loop lock GC so that we do not need to consider a case that
    // ISeq is GC-ed in a middle of re-compilation. It takes 3~4ms with 100 methods
    // on my machine. It's not too bad compared to compilation time of C (7200~8000ms),
    // but it might be larger if we use a larger --jit-max-cache.
    //
    // TODO: Consider using a more granular lock after we implement inlining across
    // compacted functions (not done yet).
    bool success = true;
    list_for_each(&active_units.head, child_unit, unode) {
        CRITICAL_SECTION_START(3, "before set_compiling_iseqs");
        success &= set_compiling_iseqs(child_unit->iseq);
        CRITICAL_SECTION_FINISH(3, "after set_compiling_iseqs");
        if (!success) continue;

        char funcname[MAXPATHLEN];
        sprint_funcname(funcname, child_unit);

        long iseq_lineno = 0;
        if (FIXNUM_P(child_unit->iseq->body->location.first_lineno))
            // FIX2INT may fallback to rb_num2long(), which is a method call and dangerous in MJIT worker. So using only FIX2LONG.
            iseq_lineno = FIX2LONG(child_unit->iseq->body->location.first_lineno);
        const char *sep = "@";
        const char *iseq_label = RSTRING_PTR(child_unit->iseq->body->location.label);
        const char *iseq_path = RSTRING_PTR(rb_iseq_path(child_unit->iseq));
        if (!iseq_label) iseq_label = sep = "";
        fprintf(f, "\n/* %s%s%s:%ld */\n", iseq_label, sep, iseq_path, iseq_lineno);
        success &= mjit_compile(f, child_unit->iseq, funcname, child_unit->id);

        CRITICAL_SECTION_START(3, "before compiling_iseqs free");
        free(compiling_iseqs);
        compiling_iseqs = NULL;
        CRITICAL_SECTION_FINISH(3, "after compiling_iseqs free");
    }

    // release blocking mjit_gc_start_hook
    CRITICAL_SECTION_START(3, "after mjit_compile to wakeup client for GC");
    in_jit = false;
    verbose(3, "Sending wakeup signal to client in a mjit-worker for GC");
    rb_native_cond_signal(&mjit_client_wakeup);
    CRITICAL_SECTION_FINISH(3, "in worker to wakeup client for GC");

    fclose(f);
    return success;
}

// Compile all cached .c files and build a single .so file. Reload all JIT func from it.
// This improves the code locality for better performance in terms of iTLB and iCache.
static void
compact_all_jit_code(void)
{
    struct rb_mjit_unit *unit, *cur = 0;
    static const char c_ext[] = ".c";
    static const char so_ext[] = DLEXT;
    char c_file[MAXPATHLEN], so_file[MAXPATHLEN];

    // Abnormal use case of rb_mjit_unit that doesn't have ISeq
    unit = calloc(1, sizeof(struct rb_mjit_unit)); // To prevent GC, don't use ZALLOC
    if (unit == NULL) return;
    unit->id = current_unit_num++;
    sprint_uniq_filename(c_file, (int)sizeof(c_file), unit->id, MJIT_TMP_PREFIX, c_ext);
    sprint_uniq_filename(so_file, (int)sizeof(so_file), unit->id, MJIT_TMP_PREFIX, so_ext);

    bool success = compile_compact_jit_code(c_file);
    double start_time = real_ms_time();
    if (success) {
        success = compile_c_to_so(c_file, so_file);
        if (!mjit_opts.save_temps)
            remove_file(c_file);
    }
    double end_time = real_ms_time();

    if (success) {
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

        CRITICAL_SECTION_START(3, "in compact_all_jit_code to read list");
        list_for_each(&active_units.head, cur, unode) {
            void *func;
            char funcname[MAXPATHLEN];
            sprint_funcname(funcname, cur);

            if ((func = dlsym(handle, funcname)) == NULL) {
                mjit_warning("skipping to reload '%s' from '%s': %s", funcname, so_file, dlerror());
                continue;
            }

            if (cur->iseq) { // Check whether GCed or not
                // Usage of jit_code might be not in a critical section.
                MJIT_ATOMIC_SET(cur->iseq->body->jit_func, (mjit_func_t)func);
            }
        }
        CRITICAL_SECTION_FINISH(3, "in compact_all_jit_code to read list");
        verbose(1, "JIT compaction (%.1fms): Compacted %d methods %s -> %s", end_time - start_time, active_units.length, c_file, so_file);
    }
    else {
        free(unit);
        verbose(1, "JIT compaction failure (%.1fms): Failed to compact methods", end_time - start_time);
    }
}
#endif // USE_JIT_COMPACTION

static void *
load_func_from_so(const char *so_file, const char *funcname, struct rb_mjit_unit *unit)
{
    void *handle, *func;

    handle = dlopen(so_file, RTLD_NOW);
    if (handle == NULL) {
        mjit_warning("failure in loading code from '%s': %s", so_file, dlerror());
        return (void *)NOT_ADDED_JIT_ISEQ_FUNC;
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
        switch(*s) {
          case '\\': case '"':
            fputc('\\', f);
        }
        fputc(*s, f);
    }
    fprintf(f, "\"\n");
#endif

#ifdef _WIN32
    fprintf(f, "void _pei386_runtime_relocator(void){}\n");
    fprintf(f, "int __stdcall DllMainCRTStartup(void* hinstDLL, unsigned int fdwReason, void* lpvReserved) { return 1; }\n");
#endif
}

// Compile ISeq in UNIT and return function pointer of JIT-ed code.
// It may return NOT_COMPILED_JIT_ISEQ_FUNC if something went wrong.
static mjit_func_t
convert_unit_to_func(struct rb_mjit_unit *unit)
{
    static const char c_ext[] = ".c";
    static const char so_ext[] = DLEXT;
    char c_file[MAXPATHLEN], so_file[MAXPATHLEN], funcname[MAXPATHLEN];

    sprint_uniq_filename(c_file, (int)sizeof(c_file), unit->id, MJIT_TMP_PREFIX, c_ext);
    sprint_uniq_filename(so_file, (int)sizeof(so_file), unit->id, MJIT_TMP_PREFIX, so_ext);
    sprint_funcname(funcname, unit);

    FILE *f;
    int fd = rb_cloexec_open(c_file, c_file_access_mode, 0600);
    if (fd < 0 || (f = fdopen(fd, "w")) == NULL) {
        int e = errno;
        if (fd >= 0) (void)close(fd);
        verbose(1, "Failed to fopen '%s', giving up JIT for it (%s)", c_file, strerror(e));
        return (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
    }

    // print #include of MJIT header, etc.
    compile_prelude(f);

    // wait until mjit_gc_exit_hook is called
    CRITICAL_SECTION_START(3, "before mjit_compile to wait GC finish");
    while (in_gc) {
        verbose(3, "Waiting wakeup from GC");
        rb_native_cond_wait(&mjit_gc_wakeup, &mjit_engine_mutex);
    }
    // We need to check again here because we could've waited on GC above
    in_jit = (unit->iseq != NULL);
    if (in_jit)
        in_jit &= set_compiling_iseqs(unit->iseq);
    CRITICAL_SECTION_FINISH(3, "before mjit_compile to wait GC finish");
    if (!in_jit) {
        fclose(f);
        if (!mjit_opts.save_temps)
            remove_file(c_file);
        return (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
    }

    // To make MJIT worker thread-safe against GC.compact, copy ISeq values while `in_jit` is true.
    long iseq_lineno = 0;
    if (FIXNUM_P(unit->iseq->body->location.first_lineno))
        // FIX2INT may fallback to rb_num2long(), which is a method call and dangerous in MJIT worker. So using only FIX2LONG.
        iseq_lineno = FIX2LONG(unit->iseq->body->location.first_lineno);
    char *iseq_label = alloca(RSTRING_LEN(unit->iseq->body->location.label) + 1);
    char *iseq_path  = alloca(RSTRING_LEN(rb_iseq_path(unit->iseq)) + 1);
    strcpy(iseq_label, RSTRING_PTR(unit->iseq->body->location.label));
    strcpy(iseq_path,  RSTRING_PTR(rb_iseq_path(unit->iseq)));

    verbose(2, "start compilation: %s@%s:%ld -> %s", iseq_label, iseq_path, iseq_lineno, c_file);
    fprintf(f, "/* %s@%s:%ld */\n\n", iseq_label, iseq_path, iseq_lineno);
    bool success = mjit_compile(f, unit->iseq, funcname, unit->id);

    // release blocking mjit_gc_start_hook
    CRITICAL_SECTION_START(3, "after mjit_compile to wakeup client for GC");
    free(compiling_iseqs);
    compiling_iseqs = NULL;
    in_jit = false;
    verbose(3, "Sending wakeup signal to client in a mjit-worker for GC");
    rb_native_cond_signal(&mjit_client_wakeup);
    CRITICAL_SECTION_FINISH(3, "in worker to wakeup client for GC");

    fclose(f);
    if (!success) {
        if (!mjit_opts.save_temps)
            remove_file(c_file);
        verbose(1, "JIT failure: %s@%s:%ld -> %s", iseq_label, iseq_path, iseq_lineno, c_file);
        return (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
    }

    double start_time = real_ms_time();
    success = compile_c_to_so(c_file, so_file);
    if (!mjit_opts.save_temps)
        remove_file(c_file);
    double end_time = real_ms_time();

    if (!success) {
        verbose(2, "Failed to generate so: %s", so_file);
        return (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
    }

    void *func = load_func_from_so(so_file, funcname, unit);
    if (!mjit_opts.save_temps)
        remove_so_file(so_file, unit);

    if ((uintptr_t)func > (uintptr_t)LAST_JIT_ISEQ_FUNC) {
        verbose(1, "JIT success (%.1fms): %s@%s:%ld -> %s",
                end_time - start_time, iseq_label, iseq_path, iseq_lineno, c_file);
    }
    return (mjit_func_t)func;
}

// To see cc_entries using index returned by `mjit_capture_cc_entries` in mjit_compile.c
const struct rb_callcache **
mjit_iseq_cc_entries(const struct rb_iseq_constant_body *const body)
{
    return body->jit_unit->cc_entries;
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
            iseq->body->jit_unit->used_code_p = true;
        }

        if (cfp == ec->cfp)
            break; // reached the most recent cfp
    }
}

// MJIT info related to an existing continutaion.
struct mjit_cont {
    rb_execution_context_t *ec; // continuation ec
    struct mjit_cont *prev, *next; // used to form lists
};

// Double linked list of registered continuations. This is used to detect
// units which are in use in unload_units.
static struct mjit_cont *first_cont;

// Unload JIT code of some units to satisfy the maximum permitted
// number of units with a loaded code.
static void
unload_units(void)
{
    struct rb_mjit_unit *unit = 0, *next;
    struct mjit_cont *cont;
    int units_num = active_units.length;

    // For now, we don't unload units when ISeq is GCed. We should
    // unload such ISeqs first here.
    list_for_each_safe(&active_units.head, unit, next, unode) {
        if (unit->iseq == NULL) { // ISeq is GCed.
            remove_from_list(unit, &active_units);
            free_unit(unit);
        }
    }

    // Detect units which are in use and can't be unloaded.
    list_for_each(&active_units.head, unit, unode) {
        assert(unit->iseq != NULL && unit->handle != NULL);
        unit->used_code_p = false;
    }
    // All threads have a root_fiber which has a mjit_cont. Other normal fibers also
    // have a mjit_cont. Thus we can check ISeqs in use by scanning ec of mjit_conts.
    for (cont = first_cont; cont != NULL; cont = cont->next) {
        mark_ec_units(cont->ec);
    }
    // TODO: check stale_units and unload unused ones! (note that the unit is not associated to ISeq anymore)

    // Unload units whose total_calls is smaller than any total_calls in unit_queue.
    // TODO: make the algorithm more efficient
    long unsigned prev_queue_calls = -1;
    while (true) {
        // Calculate the next max total_calls in unit_queue
        long unsigned max_queue_calls = 0;
        list_for_each(&unit_queue.head, unit, unode) {
            if (unit->iseq != NULL && max_queue_calls < unit->iseq->body->total_calls
                    && unit->iseq->body->total_calls < prev_queue_calls) {
                max_queue_calls = unit->iseq->body->total_calls;
            }
        }
        prev_queue_calls = max_queue_calls;

        bool unloaded_p = false;
        list_for_each_safe(&active_units.head, unit, next, unode) {
            if (unit->used_code_p) // We can't unload code on stack.
                continue;

            if (max_queue_calls > unit->iseq->body->total_calls) {
                verbose(2, "Unloading unit %d (calls=%lu, threshold=%lu)",
                        unit->id, unit->iseq->body->total_calls, max_queue_calls);
                assert(unit->handle != NULL);
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

// The function implementing a worker. It is executed in a separate
// thread by rb_thread_create_mjit_thread. It compiles precompiled header
// and then compiles requested ISeqs.
void
mjit_worker(void)
{
    // Allow only `max_cache_size / 10` times (default: 10) of compaction.
    // Note: GC of compacted code has not been implemented yet.
    int max_compact_size = mjit_opts.max_cache_size / 10;
    if (max_compact_size < 10) max_compact_size = 10;

    // Run unload_units after it's requested `max_cache_size / 10` (default: 10) times.
    // This throttles the call to mitigate locking in unload_units. It also throttles JIT compaction.
    int throttle_threshold = mjit_opts.max_cache_size / 10;

#ifndef _MSC_VER
    if (pch_status == PCH_NOT_READY) {
        make_pch();
    }
#endif
    if (pch_status == PCH_FAILED) {
        mjit_enabled = false;
        CRITICAL_SECTION_START(3, "in worker to update worker_stopped");
        worker_stopped = true;
        verbose(3, "Sending wakeup signal to client in a mjit-worker");
        rb_native_cond_signal(&mjit_client_wakeup);
        CRITICAL_SECTION_FINISH(3, "in worker to update worker_stopped");
        return; // TODO: do the same thing in the latter half of mjit_finish
    }

    // main worker loop
    while (!stop_worker_p) {
        struct rb_mjit_unit *unit;

        // Wait until a unit becomes available
        CRITICAL_SECTION_START(3, "in worker dequeue");
        while ((list_empty(&unit_queue.head) || active_units.length >= mjit_opts.max_cache_size) && !stop_worker_p) {
            rb_native_cond_wait(&mjit_worker_wakeup, &mjit_engine_mutex);
            verbose(3, "Getting wakeup from client");

            // Lazily move active_units to stale_units to avoid race conditions around active_units with compaction
            if (pending_stale_p) {
                pending_stale_p = false;
                struct rb_mjit_unit *next;
                list_for_each_safe(&active_units.head, unit, next, unode) {
                    if (unit->stale_p) {
                        unit->stale_p = false;
                        remove_from_list(unit, &active_units);
                        add_to_list(unit, &stale_units);
                        // Lazily put it to unit_queue as well to avoid race conditions on jit_unit with mjit_compile.
                        mjit_add_iseq_to_process(unit->iseq, &unit->iseq->body->jit_unit->compile_info, true);
                    }
                }
            }

            // Unload some units as needed
            if (unload_requests >= throttle_threshold) {
                while (in_gc) {
                    verbose(3, "Waiting wakeup from GC");
                    rb_native_cond_wait(&mjit_gc_wakeup, &mjit_engine_mutex);
                }
                in_jit = true; // Lock GC

                RB_DEBUG_COUNTER_INC(mjit_unload_units);
                unload_units();
                unload_requests = 0;

                in_jit = false; // Unlock GC
                verbose(3, "Sending wakeup signal to client in a mjit-worker for GC");
                rb_native_cond_signal(&mjit_client_wakeup);
            }
            if (active_units.length == mjit_opts.max_cache_size && mjit_opts.wait) { // Sometimes all methods may be in use
                mjit_opts.max_cache_size++; // avoid infinite loop on `rb_mjit_wait_call`. Note that --jit-wait is just for testing.
                verbose(1, "No units can be unloaded -- incremented max-cache-size to %d for --jit-wait", mjit_opts.max_cache_size);
            }
        }
        unit = get_from_list(&unit_queue);
        CRITICAL_SECTION_FINISH(3, "in worker dequeue");

        if (unit) {
            // JIT compile
            mjit_func_t func = convert_unit_to_func(unit);
            (void)RB_DEBUG_COUNTER_INC_IF(mjit_compile_failures, func == (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC);

            CRITICAL_SECTION_START(3, "in jit func replace");
            while (in_gc) { // Make sure we're not GC-ing when touching ISeq
                verbose(3, "Waiting wakeup from GC");
                rb_native_cond_wait(&mjit_gc_wakeup, &mjit_engine_mutex);
            }
            if (unit->iseq) { // Check whether GCed or not
                if ((uintptr_t)func > (uintptr_t)LAST_JIT_ISEQ_FUNC) {
                    add_to_list(unit, &active_units);
                }
                // Usage of jit_code might be not in a critical section.
                MJIT_ATOMIC_SET(unit->iseq->body->jit_func, func);
            }
            else {
                free_unit(unit);
            }
            CRITICAL_SECTION_FINISH(3, "in jit func replace");

#if USE_JIT_COMPACTION
            // Combine .o files to one .so and reload all jit_func to improve memory locality.
            if (compact_units.length < max_compact_size
                && ((!mjit_opts.wait && unit_queue.length == 0 && active_units.length > 1)
                    || (active_units.length == mjit_opts.max_cache_size && compact_units.length * throttle_threshold <= total_unloads))) { // throttle compaction by total_unloads
                compact_all_jit_code();
            }
#endif
        }
    }

    // To keep mutex unlocked when it is destroyed by mjit_finish, don't wrap CRITICAL_SECTION here.
    worker_stopped = true;
}
