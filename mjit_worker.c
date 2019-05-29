/**********************************************************************

  mjit_worker.c - Worker for MRI method JIT compiler

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.

**********************************************************************/

// NOTE: All functions in this file are executed on MJIT worker. So don't
// call Ruby methods (C functions that may call rb_funcall) or trigger
// GC (using ZALLOC, xmalloc, xfree, etc.) in this file.

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
#include "mjit.h"
#include "gc.h"
#include "ruby_assert.h"
#include "ruby/debug.h"
#include "ruby/thread.h"

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

// The unit structure that holds metadata of ISeq for MJIT.
struct rb_mjit_unit {
    // Unique order number of unit.
    int id;
    // Dlopen handle of the loaded object file.
    void *handle;
    rb_iseq_t *iseq;
#ifndef _MSC_VER
    // This value is always set for `compact_all_jit_code`. Also used for lazy deletion.
    char *o_file;
    // true if it's inherited from parent Ruby process and lazy deletion should be skipped.
    // `o_file = NULL` can't be used to skip lazy deletion because `o_file` could be used
    // by child for `compact_all_jit_code`.
    bool o_file_inherited_p;
#endif
#if defined(_WIN32)
    // DLL cannot be removed while loaded on Windows. If this is set, it'll be lazily deleted.
    char *so_file;
#endif
    // Only used by unload_units. Flag to check this unit is currently on stack or not.
    char used_code_p;
    struct list_node unode;
    // mjit_compile's optimization switches
    struct rb_mjit_compile_info compile_info;
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
// True when GC is working.
static bool in_gc;
// True when JIT is working.
static bool in_jit;
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
static const char *const CC_DLDFLAGS_ARGS[] = {
    MJIT_DLDFLAGS
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

// Lazily delete .o and/or .so files.
static void
clean_object_files(struct rb_mjit_unit *unit)
{
#ifndef _MSC_VER
    if (unit->o_file) {
        char *o_file = unit->o_file;

        unit->o_file = NULL;
        // For compaction, unit->o_file is always set when compilation succeeds.
        // So save_temps needs to be checked here.
        if (!mjit_opts.save_temps && !unit->o_file_inherited_p)
            remove_file(o_file);
        free(o_file);
    }
#endif

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
    if (unit->handle && dlclose(unit->handle)) { // handle is NULL if it's in queue
        mjit_warning("failed to close handle for u%d: %s", unit->id, dlerror());
    }
    clean_object_files(unit);
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
    struct rb_mjit_unit *unit = NULL, *next, *best = NULL;

    // Find iseq with max total_calls
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
            return NULL;
        }
        res = tmp;
        MEMCPY(res + len, args, char *, n + 1);
        len += n;
    }
    va_end(argp);
    return res;
}

COMPILER_WARNING_PUSH
#ifdef __GNUC__
COMPILER_WARNING_IGNORED(-Wdeprecated-declarations)
#endif
// Start an OS process of absolute executable path with arguments `argv`.
// Return PID of the process.
static pid_t
start_process(const char *abspath, char *const *argv)
{
    pid_t pid;
    // Not calling non-async-signal-safe functions between vfork
    // and execv for safety
    int dev_null = rb_cloexec_open(ruby_null_device, O_WRONLY, 0);

    if (mjit_opts.verbose >= 2) {
        int i;
        const char *arg;

        fprintf(stderr, "Starting process: %s", abspath);
        for (i = 0; (arg = argv[i]) != NULL; i++)
            fprintf(stderr, " %s", arg);
        fprintf(stderr, "\n");
    }
#ifdef _WIN32
    {
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
    pid_t pid;
    rb_vm_t *vm = WAITPID_USE_SIGCHLD ? GET_VM() : 0;
    rb_nativethread_cond_t cond;

    if (vm) {
        rb_native_cond_initialize(&cond);
        rb_native_mutex_lock(&vm->waitpid_lock);
    }

    pid = start_process(path, argv);
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
    unit->so_file = strdup(so_file); // lazily delete on `clean_object_files()`
    if (unit->so_file == NULL)
        mjit_warning("failed to allocate memory to lazily remove '%s': %s", so_file, strerror(errno));
#else
    remove_file(so_file);
#endif
}

#define append_str2(p, str, len) ((char *)memcpy((p), str, (len))+(len))
#define append_str(p, str) append_str2(p, str, sizeof(str)-1)
#define append_lit(p, str) append_str2(p, str, rb_strlen_lit(str))

#ifdef _MSC_VER
// Compile C file to so. It returns true if it succeeds. (mswin)
static bool
compile_c_to_so(const char *c_file, const char *so_file)
{
    int exit_code;
    const char *files[] = { NULL, NULL, NULL, NULL, NULL, NULL, "-link", libruby_pathflag, NULL };
    char **args;
    char *p, *obj_file;

    // files[0] = "-Fe*.dll"
    files[0] = p = alloca(sizeof(char) * (rb_strlen_lit("-Fe") + strlen(so_file) + 1));
    p = append_lit(p, "-Fe");
    p = append_str2(p, so_file, strlen(so_file));
    *p = '\0';

    // files[1] = "-Fo*.obj"
    // We don't need .obj file, but it's somehow created to cwd without -Fo and we want to control the output directory.
    files[1] = p = alloca(sizeof(char) * (rb_strlen_lit("-Fo") + strlen(so_file) - rb_strlen_lit(DLEXT) + rb_strlen_lit(".obj") + 1));
    obj_file = p = append_lit(p, "-Fo");
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

    args = form_args(5, CC_LDSHARED_ARGS, CC_CODEFLAG_ARGS,
                     files, CC_LIBS, CC_DLDFLAGS_ARGS);
    if (args == NULL)
        return false;

    exit_code = exec_process(cc_path, args);
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
    int exit_code;
    const char *rest_args[] = {
# ifdef __clang__
        "-emit-pch",
# endif
        // -nodefaultlibs is a linker flag, but it may affect cc1 behavior on Gentoo, which should NOT be changed on pch:
        // https://gitweb.gentoo.org/proj/gcc-patches.git/tree/7.3.0/gentoo/13_all_default-ssp-fix.patch
        GCC_NOSTDLIB_FLAGS
        "-o", NULL, NULL,
        NULL,
    };
    char **args;
    int len = sizeof(rest_args) / sizeof(const char *);

    rest_args[len - 2] = header_file;
    rest_args[len - 3] = pch_file;
    verbose(2, "Creating precompiled header");
    args = form_args(3, cc_common_args, CC_CODEFLAG_ARGS, rest_args);
    if (args == NULL) {
        mjit_warning("making precompiled header failed on forming args");
        CRITICAL_SECTION_START(3, "in make_pch");
        pch_status = PCH_FAILED;
        CRITICAL_SECTION_FINISH(3, "in make_pch");
        return;
    }

    exit_code = exec_process(cc_path, args);
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

// Compile .c file to .o file. It returns true if it succeeds. (non-mswin)
static bool
compile_c_to_o(const char *c_file, const char *o_file)
{
    int exit_code;
    const char *files[] = {
        "-o", NULL, NULL,
# ifdef __clang__
        "-include-pch", NULL,
# endif
        "-c", NULL
    };
    char **args;

    files[1] = o_file;
    files[2] = c_file;
# ifdef __clang__
    files[4] = pch_file;
# endif
    args = form_args(5, cc_common_args, CC_CODEFLAG_ARGS, files, CC_LIBS, CC_DLDFLAGS_ARGS);
    if (args == NULL)
        return false;

    exit_code = exec_process(cc_path, args);
    free(args);

    if (exit_code != 0)
        verbose(2, "compile_c_to_o: compile error: %d", exit_code);
    return exit_code == 0;
}

// Link .o files to .so file. It returns true if it succeeds. (non-mswin)
static bool
link_o_to_so(const char **o_files, const char *so_file)
{
    int exit_code;
    const char *options[] = {
        "-o", NULL,
# ifdef _WIN32
        libruby_pathflag,
# endif
        NULL
    };
    char **args;

    options[1] = so_file;
    args = form_args(6, CC_LDSHARED_ARGS, CC_CODEFLAG_ARGS,
                     options, o_files, CC_LIBS, CC_DLDFLAGS_ARGS);
    if (args == NULL)
        return false;

    exit_code = exec_process(cc_path, args);
    free(args);

    if (exit_code != 0)
        verbose(2, "link_o_to_so: link error: %d", exit_code);
    return exit_code == 0;
}

// Link all cached .o files and build a .so file. Reload all JIT func from it. This
// allows to avoid JIT code fragmentation and improve performance to call JIT-ed code.
static void
compact_all_jit_code(void)
{
# ifndef _WIN32 // This requires header transformation but we don't transform header on Windows for now
    struct rb_mjit_unit *unit, *cur = 0;
    double start_time, end_time;
    static const char so_ext[] = DLEXT;
    char so_file[MAXPATHLEN];
    const char **o_files;
    int i = 0;

    // Abnormal use case of rb_mjit_unit that doesn't have ISeq
    unit = calloc(1, sizeof(struct rb_mjit_unit)); // To prevent GC, don't use ZALLOC
    if (unit == NULL) return;
    unit->id = current_unit_num++;
    sprint_uniq_filename(so_file, (int)sizeof(so_file), unit->id, MJIT_TMP_PREFIX, so_ext);

    // NULL-ending for form_args
    o_files = alloca(sizeof(char *) * (active_units.length + 1));
    o_files[active_units.length] = NULL;
    CRITICAL_SECTION_START(3, "in compact_all_jit_code to keep .o files");
    list_for_each(&active_units.head, cur, unode) {
        o_files[i] = cur->o_file;
        i++;
    }

    start_time = real_ms_time();
    bool success = link_o_to_so(o_files, so_file);
    end_time = real_ms_time();

    // TODO: Shrink this big critical section. For now, this is needed to prevent failure by missing .o files.
    // This assumes that o -> so link doesn't take long time because the bottleneck, which is compiler optimization,
    // is already done. But actually it takes about 500ms for 5,000 methods on my Linux machine, so it's better to
    // finish this critical section before link_o_to_so by disabling unload_units.
    CRITICAL_SECTION_FINISH(3, "in compact_all_jit_code to keep .o files");

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
            char funcname[35]; // TODO: reconsider `35`
            sprintf(funcname, "_mjit%d", cur->id);

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
        verbose(1, "JIT compaction (%.1fms): Compacted %d methods -> %s", end_time - start_time, active_units.length, so_file);
    }
    else {
        free(unit);
        verbose(1, "JIT compaction failure (%.1fms): Failed to compact methods", end_time - start_time);
    }
# endif // _WIN32
}

#endif // _MSC_VER

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
    char c_file_buff[MAXPATHLEN], *c_file = c_file_buff, *so_file, funcname[35]; // TODO: reconsider `35`
    int fd;
    FILE *f;
    void *func;
    double start_time, end_time;
    int c_file_len = (int)sizeof(c_file_buff);
    static const char c_ext[] = ".c";
    static const char so_ext[] = DLEXT;
    const int access_mode =
#ifdef O_BINARY
        O_BINARY|
#endif
        O_WRONLY|O_EXCL|O_CREAT;
#ifndef _MSC_VER
    static const char o_ext[] = ".o";
    char *o_file;
#endif

    c_file_len = sprint_uniq_filename(c_file_buff, c_file_len, unit->id, MJIT_TMP_PREFIX, c_ext);
    if (c_file_len >= (int)sizeof(c_file_buff)) {
        ++c_file_len;
        c_file = alloca(c_file_len);
        c_file_len = sprint_uniq_filename(c_file, c_file_len, unit->id, MJIT_TMP_PREFIX, c_ext);
    }
    ++c_file_len;

#ifndef _MSC_VER
    o_file = alloca(c_file_len - sizeof(c_ext) + sizeof(o_ext));
    memcpy(o_file, c_file, c_file_len - sizeof(c_ext));
    memcpy(&o_file[c_file_len - sizeof(c_ext)], o_ext, sizeof(o_ext));
#endif
    so_file = alloca(c_file_len - sizeof(c_ext) + sizeof(so_ext));
    memcpy(so_file, c_file, c_file_len - sizeof(c_ext));
    memcpy(&so_file[c_file_len - sizeof(c_ext)], so_ext, sizeof(so_ext));

    sprintf(funcname, "_mjit%d", unit->id);

    fd = rb_cloexec_open(c_file, access_mode, 0600);
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
    if (unit->iseq == NULL) {
        fclose(f);
        if (!mjit_opts.save_temps)
            remove_file(c_file);
        free_unit(unit);
        in_jit = false; // just being explicit for return
    }
    else {
        in_jit = true;
    }
    CRITICAL_SECTION_FINISH(3, "before mjit_compile to wait GC finish");
    if (!in_jit) {
        return (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
    }

    // To make MJIT worker thread-safe against GC.compact, copy ISeq values while `in_jit` is true.
    long iseq_lineno = 0;
    if (FIXNUM_P(unit->iseq->body->location.first_lineno))
        // FIX2INT may fallback to rb_num2long(), which is a method call and dangerous in MJIT worker. So using only FIX2LONG.
        iseq_lineno = FIX2LONG(unit->iseq->body->location.first_lineno);
    char *iseq_label = alloca(RSTRING_LEN(unit->iseq->body->location.label));
    char *iseq_path  = alloca(RSTRING_LEN(rb_iseq_path(unit->iseq)));
    strcpy(iseq_label, RSTRING_PTR(unit->iseq->body->location.label));
    strcpy(iseq_path,  RSTRING_PTR(rb_iseq_path(unit->iseq)));

    verbose(2, "start compilation: %s@%s:%ld -> %s", iseq_label, iseq_path, iseq_lineno, c_file);
    fprintf(f, "/* %s@%s:%ld */\n\n", iseq_label, iseq_path, iseq_lineno);
    bool success = mjit_compile(f, unit->iseq, funcname);

    // release blocking mjit_gc_start_hook
    CRITICAL_SECTION_START(3, "after mjit_compile to wakeup client for GC");
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

    start_time = real_ms_time();
#ifdef _MSC_VER
    success = compile_c_to_so(c_file, so_file);
#else
    // splitting .c -> .o step and .o -> .so step, to cache .o files in the future
    if ((success = compile_c_to_o(c_file, o_file)) != false) {
        const char *o_files[2] = { NULL, NULL };
        o_files[0] = o_file;
        success = link_o_to_so(o_files, so_file);

        // Always set o_file for compaction. The value is also used for lazy deletion.
        unit->o_file = strdup(o_file);
        if (unit->o_file == NULL) {
            mjit_warning("failed to allocate memory to remember '%s' (%s), removing it...", o_file, strerror(errno));
            remove_file(o_file);
        }
    }
#endif
    end_time = real_ms_time();

    if (!mjit_opts.save_temps)
        remove_file(c_file);
    if (!success) {
        verbose(2, "Failed to generate so: %s", so_file);
        return (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
    }

    func = load_func_from_so(so_file, funcname, unit);
    if (!mjit_opts.save_temps)
        remove_so_file(so_file, unit);

    if ((uintptr_t)func > (uintptr_t)LAST_JIT_ISEQ_FUNC) {
        CRITICAL_SECTION_START(3, "end of jit");
        add_to_list(unit, &active_units);
        verbose(1, "JIT success (%.1fms): %s@%s:%ld -> %s",
                end_time - start_time, iseq_label, iseq_path, iseq_lineno, c_file);
        CRITICAL_SECTION_FINISH(3, "end of jit");
    }
    return (mjit_func_t)func;
}

typedef struct {
    const rb_iseq_t *iseq;
    struct rb_call_cache *cc_entries;
    union iseq_inline_storage_entry *is_entries;
    bool finish_p;
} mjit_copy_job_t;

// Singleton MJIT copy job. This is made global since it needs to be durable even when MJIT worker thread is stopped.
// (ex: register job -> MJIT pause -> MJIT resume -> dispatch job. Actually this should be just cancelled by finish_p check)
static mjit_copy_job_t mjit_copy_job = { .iseq = NULL, .finish_p = true };

static void mjit_copy_job_handler(void *data);

// vm_trace.c
int rb_workqueue_register(unsigned flags, rb_postponed_job_func_t , void *);

// Copy inline cache values of `iseq` to `cc_entries` and `is_entries`.
// These buffers should be pre-allocated properly prior to calling this function.
// Return true if copy succeeds or is not needed.
//
// We're lazily copying cache values from main thread because these cache values
// could be different between ones on enqueue timing and ones on dequeue timing.
bool
mjit_copy_cache_from_main_thread(const rb_iseq_t *iseq, struct rb_call_cache *cc_entries, union iseq_inline_storage_entry *is_entries)
{
    mjit_copy_job_t *job = &mjit_copy_job; // just a short hand

    CRITICAL_SECTION_START(3, "in mjit_copy_cache_from_main_thread");
    job->finish_p = true; // disable dispatching this job in mjit_copy_job_handler while it's being modified
    CRITICAL_SECTION_FINISH(3, "in mjit_copy_cache_from_main_thread");

    job->cc_entries = cc_entries;
    job->is_entries = is_entries;

    CRITICAL_SECTION_START(3, "in mjit_copy_cache_from_main_thread");
    job->iseq = iseq; // Prevernt GC of this ISeq from here
    VM_ASSERT(in_jit);
    in_jit = false; // To avoid deadlock, allow running GC while waiting for copy job
    rb_native_cond_signal(&mjit_client_wakeup); // Unblock main thread waiting in `mjit_gc_start_hook`

    job->finish_p = false; // allow dispatching this job in mjit_copy_job_handler
    CRITICAL_SECTION_FINISH(3, "in mjit_copy_cache_from_main_thread");

    if (UNLIKELY(mjit_opts.wait)) {
        mjit_copy_job_handler((void *)job);
    }
    else if (rb_workqueue_register(0, mjit_copy_job_handler, (void *)job)) {
        CRITICAL_SECTION_START(3, "in MJIT copy job wait");
        // checking `stop_worker_p` too because `RUBY_VM_CHECK_INTS(ec)` may not
        // lush mjit_copy_job_handler when EC_EXEC_TAG() is not TAG_NONE, and then
        // `stop_worker()` could dead lock with this function.
        while (!job->finish_p && !stop_worker_p) {
            rb_native_cond_wait(&mjit_worker_wakeup, &mjit_engine_mutex);
            verbose(3, "Getting wakeup from client");
        }
        CRITICAL_SECTION_FINISH(3, "in MJIT copy job wait");
    }

    CRITICAL_SECTION_START(3, "in mjit_copy_cache_from_main_thread");
    bool success_p = job->finish_p;
    // Disable dispatching this job in mjit_copy_job_handler while memory allocated by alloca
    // could be expired after finishing this function.
    job->finish_p = true;

    in_jit = true; // Prohibit GC during JIT compilation
    if (job->iseq == NULL) // ISeq GC is notified in mjit_mark_iseq
        success_p = false;
    job->iseq = NULL; // Allow future GC of this ISeq from here
    CRITICAL_SECTION_FINISH(3, "in mjit_copy_cache_from_main_thread");
    return success_p;
}

// The function implementing a worker. It is executed in a separate
// thread by rb_thread_create_mjit_thread. It compiles precompiled header
// and then compiles requested ISeqs.
void
mjit_worker(void)
{
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

        // wait until unit is available
        CRITICAL_SECTION_START(3, "in worker dequeue");
        while ((list_empty(&unit_queue.head) || active_units.length >= mjit_opts.max_cache_size) && !stop_worker_p) {
            rb_native_cond_wait(&mjit_worker_wakeup, &mjit_engine_mutex);
            verbose(3, "Getting wakeup from client");
        }
        unit = get_from_list(&unit_queue);
        CRITICAL_SECTION_FINISH(3, "in worker dequeue");

        if (unit) {
            // JIT compile
            mjit_func_t func = convert_unit_to_func(unit);
            (void)RB_DEBUG_COUNTER_INC_IF(mjit_compile_failures, func == (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC);

            // `mjit_copy_cache_from_main_thread` in `mjit_compile` may wait for a long time
            // and worker may be stopped during the compilation.
            if (stop_worker_p)
                break;

            CRITICAL_SECTION_START(3, "in jit func replace");
            while (in_gc) { // Make sure we're not GC-ing when touching ISeq
                verbose(3, "Waiting wakeup from GC");
                rb_native_cond_wait(&mjit_gc_wakeup, &mjit_engine_mutex);
            }
            if (unit->iseq) { // Check whether GCed or not
                // Usage of jit_code might be not in a critical section.
                MJIT_ATOMIC_SET(unit->iseq->body->jit_func, func);
            }
            CRITICAL_SECTION_FINISH(3, "in jit func replace");

#ifndef _MSC_VER
            // Combine .o files to one .so and reload all jit_func to improve memory locality
            if ((!mjit_opts.wait && unit_queue.length == 0 && active_units.length > 1)
                || active_units.length == mjit_opts.max_cache_size) {
                compact_all_jit_code();
            }
#endif
        }
    }

    // To keep mutex unlocked when it is destroyed by mjit_finish, don't wrap CRITICAL_SECTION here.
    worker_stopped = true;
}
