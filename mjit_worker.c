/**********************************************************************

  mjit_worker.c - Worker for MRI method JIT compiler

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.

**********************************************************************/

/* NOTE: All functions in this file are executed on MJIT worker. So don't
   call Ruby methods (C functions that may call rb_funcall) or trigger
   GC (using xmalloc, ZALLOC, etc.) in this file. */

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

#include "internal.h"
#include "vm_core.h"
#include "mjit.h"
#include "gc.h"
#include "ruby_assert.h"
#include "ruby/thread.h"
#include "ruby/util.h"

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

#ifndef MAXPATHLEN
# define MAXPATHLEN 1024
#endif

#ifdef _WIN32
#define dlopen(name,flag) ((void*)LoadLibrary(name))
#define dlerror() strerror(rb_w32_map_errno(GetLastError()))
#define dlsym(handle,name) ((void*)GetProcAddress((handle),(name)))
#define dlclose(handle) (FreeLibrary(handle))
#define RTLD_NOW  -1
#endif

#define MJIT_TMP_PREFIX "_ruby_mjit_"

/* The unit structure that holds metadata of ISeq for MJIT.  */
struct rb_mjit_unit {
    /* Unique order number of unit.  */
    int id;
    /* Dlopen handle of the loaded object file.  */
    void *handle;
    const rb_iseq_t *iseq;
#ifndef _MSC_VER
    /* This value is always set for `compact_all_jit_code`. Also used for lazy deletion. */
    char *o_file;
#endif
#ifdef _WIN32
    /* DLL cannot be removed while loaded on Windows. If this is set, it'll be lazily deleted. */
    char *so_file;
#endif
    /* Only used by unload_units. Flag to check this unit is currently on stack or not. */
    char used_code_p;
};

/* Node of linked list in struct rb_mjit_unit_list.
   TODO: use ccan/list for this */
struct rb_mjit_unit_node {
    struct rb_mjit_unit *unit;
    struct rb_mjit_unit_node *next, *prev;
};

/* Linked list of struct rb_mjit_unit.  */
struct rb_mjit_unit_list {
    struct rb_mjit_unit_node *head;
    int length; /* the list length */
};

enum pch_status_t {PCH_NOT_READY, PCH_FAILED, PCH_SUCCESS};

extern void rb_native_mutex_lock(rb_nativethread_lock_t *lock);
extern void rb_native_mutex_unlock(rb_nativethread_lock_t *lock);
extern void rb_native_mutex_initialize(rb_nativethread_lock_t *lock);
extern void rb_native_mutex_destroy(rb_nativethread_lock_t *lock);

extern void rb_native_cond_initialize(rb_nativethread_cond_t *cond);
extern void rb_native_cond_destroy(rb_nativethread_cond_t *cond);
extern void rb_native_cond_signal(rb_nativethread_cond_t *cond);
extern void rb_native_cond_broadcast(rb_nativethread_cond_t *cond);
extern void rb_native_cond_wait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex);

extern char *mjit_tmp_dir;

static int
sprint_uniq_filename(char *str, size_t size, unsigned long id, const char *prefix, const char *suffix)
{
    return snprintf(str, size, "%s/%sp%"PRI_PIDT_PREFIX"uu%lu%s", mjit_tmp_dir, prefix, getpid(), id, suffix);
}

/* Print the arguments according to FORMAT to stderr only if MJIT
   verbose option value is more or equal to LEVEL.  */
PRINTF_ARGS(static void, 2, 3)
verbose(int level, const char *format, ...)
{
    va_list args;

    va_start(args, format);
    if (mjit_opts.verbose >= level)
        vfprintf(stderr, format, args);
    va_end(args);
    if (mjit_opts.verbose >= level)
        fprintf(stderr, "\n");
}

extern rb_nativethread_lock_t mjit_engine_mutex;

/* Start a critical section.  Use message MSG to print debug info at
   LEVEL.  */
static inline void
CRITICAL_SECTION_START(int level, const char *msg)
{
    verbose(level, "Locking %s", msg);
    rb_native_mutex_lock(&mjit_engine_mutex);
    verbose(level, "Locked %s", msg);
}

/* Finish the current critical section.  Use message MSG to print
   debug info at LEVEL. */
static inline void
CRITICAL_SECTION_FINISH(int level, const char *msg)
{
    verbose(level, "Unlocked %s", msg);
    rb_native_mutex_unlock(&mjit_engine_mutex);
}

/* Allocate struct rb_mjit_unit_node and return it. This MUST NOT be
   called inside critical section because that causes deadlock. ZALLOC
   may fire GC and GC hooks mjit_gc_start_hook that starts critical section. */
static struct rb_mjit_unit_node *
create_list_node(struct rb_mjit_unit *unit)
{
    struct rb_mjit_unit_node *node = ZALLOC(struct rb_mjit_unit_node);
    node->unit = unit;
    return node;
}

/* Add unit node to the tail of doubly linked LIST.  It should be not in
   the list before.  */
static void
add_to_list(struct rb_mjit_unit_node *node, struct rb_mjit_unit_list *list)
{
    /* Append iseq to list */
    if (list->head == NULL) {
        list->head = node;
    }
    else {
        struct rb_mjit_unit_node *tail = list->head;
        while (tail->next != NULL) {
            tail = tail->next;
        }
        tail->next = node;
        node->prev = tail;
    }
    list->length++;
}

static void
remove_from_list(struct rb_mjit_unit_node *node, struct rb_mjit_unit_list *list)
{
    if (node->prev && node->next) {
        node->prev->next = node->next;
        node->next->prev = node->prev;
    }
    else if (node->prev == NULL && node->next) {
        list->head = node->next;
        node->next->prev = NULL;
    }
    else if (node->prev && node->next == NULL) {
        node->prev->next = NULL;
    }
    else {
        list->head = NULL;
    }
    list->length--;
    xfree(node);
}

static void
remove_file(const char *filename)
{
    if (remove(filename) && (mjit_opts.warnings || mjit_opts.verbose)) {
        fprintf(stderr, "MJIT warning: failed to remove \"%s\": %s\n",
                filename, strerror(errno));
    }
}

/* Lazily delete .o and/or .so files. */
static void
clean_object_files(struct rb_mjit_unit *unit)
{
#ifndef _MSC_VER
    if (unit->o_file) {
        char *o_file = unit->o_file;

        unit->o_file = NULL;
        /* For compaction, unit->o_file is always set when compilation succeeds.
           So save_temps needs to be checked here. */
        if (!mjit_opts.save_temps)
            remove_file(o_file);
        free(o_file);
    }
#endif

#ifdef _WIN32
    if (unit->so_file) {
        char *so_file = unit->so_file;

        unit->so_file = NULL;
        /* unit->so_file is set only when mjit_opts.save_temps is FALSE. */
        remove_file(so_file);
        free(so_file);
    }
#endif
}

/* This is called in the following situations:
   1) On dequeue or `unload_units()`, associated ISeq is already GCed.
   2) The unit is not called often and unloaded by `unload_units()`.
   3) Freeing lists on `mjit_finish()`.

   `jit_func` value does not matter for 1 and 3 since the unit won't be used anymore.
   For the situation 2, this sets the ISeq's JIT state to NOT_COMPILED_JIT_ISEQ_FUNC
   to prevent the situation that the same methods are continously compiled.  */
static void
free_unit(struct rb_mjit_unit *unit)
{
    if (unit->iseq) { /* ISeq is not GCed */
        unit->iseq->body->jit_func = (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
        unit->iseq->body->jit_unit = NULL;
    }
    if (unit->handle) /* handle is NULL if it's in queue */
        dlclose(unit->handle);
    clean_object_files(unit);
    xfree(unit);
}

#define append_str2(p, str, len) ((char *)memcpy((p), str, (len))+(len))
#define append_str(p, str) append_str2(p, str, sizeof(str)-1)
#define append_lit(p, str) append_str2(p, str, rb_strlen_lit(str))

#include "mjit_config.h"

#if defined(__GNUC__) && \
     (!defined(__clang__) || \
      (defined(__clang__) && (defined(__FreeBSD__) || defined(__GLIBC__))))
#define GCC_PIC_FLAGS "-Wfatal-errors", "-fPIC", "-shared", "-w", \
    "-pipe",
#else
#define GCC_PIC_FLAGS /* empty */
#endif

static const char *const CC_COMMON_ARGS[] = {
    MJIT_CC_COMMON MJIT_CFLAGS GCC_PIC_FLAGS
    NULL
};

/* GCC and CLANG executable paths.  TODO: The paths should absolute
   ones to prevent changing C compiler for security reasons.  */
#define CC_PATH CC_COMMON_ARGS[0]

#ifdef _WIN32
#define waitpid(pid,stat_loc,options) (WaitForSingleObject((HANDLE)(pid), INFINITE), GetExitCodeProcess((HANDLE)(pid), (LPDWORD)(stat_loc)), (pid))
#define WIFEXITED(S) ((S) != STILL_ACTIVE)
#define WEXITSTATUS(S) (S)
#define WIFSIGNALED(S) (0)
typedef intptr_t pid_t;
#endif

/* process.c */
rb_pid_t ruby_waitpid_locked(rb_vm_t *, rb_pid_t, int *status, int options,
                          rb_nativethread_cond_t *cond);

/* Atomically set function pointer if possible. */
#define MJIT_ATOMIC_SET(var, val) (void)ATOMIC_PTR_EXCHANGE(var, val)

extern struct mjit_options mjit_opts;
extern int mjit_enabled;

extern struct rb_mjit_unit_list mjit_unit_queue;
extern struct rb_mjit_unit_list mjit_active_units;
extern struct rb_mjit_unit_list mjit_compact_units;
extern int mjit_current_unit_num;
extern rb_nativethread_cond_t mjit_pch_wakeup;
extern rb_nativethread_cond_t mjit_client_wakeup;
extern rb_nativethread_cond_t mjit_worker_wakeup;
extern rb_nativethread_cond_t mjit_gc_wakeup;

extern int mjit_in_gc;
extern int mjit_in_jit;

/* --- Defined in the client thread before starting MJIT threads: ---  */
/* Used C compiler path.  */
const char *mjit_cc_path;
/* Name of the precompiled header file.  */
char *mjit_pch_file;

#ifndef _MSC_VER
/* Name of the header file.  */
char *mjit_header_file;
#endif

#ifdef _WIN32
/* Linker option to enable libruby. */
char *mjit_libruby_pathflag;
#endif

/* Return time in milliseconds as a double.  */
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

static const char *const CC_DEBUG_ARGS[] = {MJIT_DEBUGFLAGS NULL};
static const char *const CC_OPTIMIZE_ARGS[] = {MJIT_OPTFLAGS NULL};

static const char *const CC_LDSHARED_ARGS[] = {MJIT_LDSHARED GCC_PIC_FLAGS NULL};
static const char *const CC_DLDFLAGS_ARGS[] = {
    MJIT_DLDFLAGS
#if defined __GNUC__ && !defined __clang__
    "-nostartfiles",
# if !defined(_WIN32) && !defined(__CYGWIN__)
    "-nodefaultlibs", "-nostdlib",
# endif
#endif
    NULL
};

static const char *const CC_LIBS[] = {
#if defined(_WIN32) || defined(__CYGWIN__)
    MJIT_LIBS
# if defined __GNUC__ && !defined __clang__
#  if defined(_WIN32)
    "-lmsvcrt",
#  endif
    "-lgcc",
# endif
#endif
    NULL
};

#define CC_CODEFLAG_ARGS (mjit_opts.debug ? CC_DEBUG_ARGS : CC_OPTIMIZE_ARGS)

/* Status of the precompiled header creation.  The status is
   shared by the workers and the pch thread.  */
enum pch_status_t mjit_pch_status;

/* Return TRUE if class_serial is not obsoleted. */
int
mjit_valid_class_serial_p(rb_serial_t class_serial)
{
    extern VALUE mjit_valid_class_serials;
    int found_p;

    CRITICAL_SECTION_START(3, "in valid_class_serial_p");
    found_p = st_lookup(RHASH_TBL_RAW(mjit_valid_class_serials), LONG2FIX(class_serial), NULL);
    CRITICAL_SECTION_FINISH(3, "in valid_class_serial_p");
    return found_p;
}

/* Return the best unit from list.  The best is the first
   high priority unit or the unit whose iseq has the biggest number
   of calls so far.  */
static struct rb_mjit_unit_node *
get_from_list(struct rb_mjit_unit_list *list)
{
    struct rb_mjit_unit_node *node, *best = NULL;

    if (list->head == NULL)
        return NULL;

    /* Find iseq with max total_calls */
    for (node = list->head; node != NULL; node = node ? node->next : NULL) {
        if (node->unit->iseq == NULL) { /* ISeq is GCed. */
            free_unit(node->unit);
            remove_from_list(node, list);
            continue;
        }

        if (best == NULL || best->unit->iseq->body->total_calls < node->unit->iseq->body->total_calls) {
            best = node;
        }
    }

    return best;
}

/* Return length of NULL-terminated array ARGS excluding the NULL
   marker.  */
static size_t
args_len(char *const *args)
{
    size_t i;

    for (i = 0; (args[i]) != NULL;i++)
        ;
    return i;
}

/* Concatenate NUM passed NULL-terminated arrays of strings, put the
   result (with NULL end marker) into the heap, and return the
   result.  */
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
/* Start an OS process of executable PATH with arguments ARGV.  Return
   PID of the process.
   TODO: Use the same function in process.c */
static pid_t
start_process(const char *path, char *const *argv)
{
    pid_t pid;

    if (mjit_opts.verbose >= 2) {
        int i;
        const char *arg;

        fprintf(stderr, "Starting process: %s", path);
        for (i = 0; (arg = argv[i]) != NULL; i++)
            fprintf(stderr, " %s", arg);
        fprintf(stderr, "\n");
    }
#ifdef _WIN32
    pid = spawnvp(_P_NOWAIT, path, argv);
#else
    {
        /*
         * Not calling non-async-signal-safe functions between vfork
         * and execv for safety
         */
        char fbuf[MAXPATHLEN];
        const char *abspath = dln_find_exe_r(path, 0, fbuf, sizeof(fbuf));
        int dev_null;

        if (!abspath) {
            verbose(1, "MJIT: failed to find `%s' in PATH\n", path);
            return -1;
        }
        dev_null = rb_cloexec_open(ruby_null_device, O_WRONLY, 0);

        if ((pid = vfork()) == 0) {
            umask(0077);
            if (mjit_opts.verbose == 0) {
                /* CC can be started in a thread using a file which has been
                   already removed while MJIT is finishing.  Discard the
                   messages about missing files.  */
                dup2(dev_null, STDERR_FILENO);
                dup2(dev_null, STDOUT_FILENO);
            }
            (void)close(dev_null);
            pid = execv(abspath, argv); /* Pid will be negative on an error */
            /* Even if we successfully found CC to compile PCH we still can
             fail with loading the CC in very rare cases for some reasons.
             Stop the forked process in this case.  */
            verbose(1, "MJIT: Error in execv: %s\n", abspath);
            _exit(1);
        }
        (void)close(dev_null);
    }
#endif
    return pid;
}
COMPILER_WARNING_POP

/* Execute an OS process of executable PATH with arguments ARGV.
   Return -1 or -2 if failed to execute, otherwise exit code of the process.
   TODO: Use a similar function in process.c */
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
            } else if (WIFSIGNALED(stat)) {
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

#ifdef _MSC_VER
/* Compile C file to so. It returns 1 if it succeeds. (mswin) */
static int
compile_c_to_so(const char *c_file, const char *so_file)
{
    int exit_code;
    const char *files[] = { NULL, NULL, NULL, NULL, "-link", mjit_libruby_pathflag, NULL };
    char **args;
    char *p;

    /* files[0] = "-Fe*.dll" */
    files[0] = p = (char *)alloca(sizeof(char) * (rb_strlen_lit("-Fe") + strlen(so_file) + 1));
    p = append_lit(p, "-Fe");
    p = append_str2(p, so_file, strlen(so_file));
    *p = '\0';

    /* files[1] = "-Yu*.pch" */
    files[1] = p = (char *)alloca(sizeof(char) * (rb_strlen_lit("-Yu") + strlen(mjit_pch_file) + 1));
    p = append_lit(p, "-Yu");
    p = append_str2(p, mjit_pch_file, strlen(mjit_pch_file));
    *p = '\0';

    /* files[2] = "C:/.../rb_mjit_header-*.obj" */
    files[2] = p = (char *)alloca(sizeof(char) * (strlen(mjit_pch_file) + 1));
    p = append_str2(p, mjit_pch_file, strlen(mjit_pch_file) - strlen(".pch"));
    p = append_lit(p, ".obj");
    *p = '\0';

    /* files[3] = "-Tc*.c" */
    files[3] = p = (char *)alloca(sizeof(char) * (rb_strlen_lit("-Tc") + strlen(c_file) + 1));
    p = append_lit(p, "-Tc");
    p = append_str2(p, c_file, strlen(c_file));
    *p = '\0';

    args = form_args(5, CC_LDSHARED_ARGS, CC_CODEFLAG_ARGS,
                     files, CC_LIBS, CC_DLDFLAGS_ARGS);
    if (args == NULL)
        return FALSE;

    {
        int stdout_fileno = _fileno(stdout);
        int orig_fd = dup(stdout_fileno);
        int dev_null = rb_cloexec_open(ruby_null_device, O_WRONLY, 0);

        /* Discard cl.exe's outputs like:
             _ruby_mjit_p12u3.c
               Creating library C:.../_ruby_mjit_p12u3.lib and object C:.../_ruby_mjit_p12u3.exp
           TODO: Don't discard them on --jit-verbose=2+ */
        dup2(dev_null, stdout_fileno);
        exit_code = exec_process(mjit_cc_path, args);
        dup2(orig_fd, stdout_fileno);

        close(orig_fd);
        close(dev_null);
    }
    free(args);

    if (exit_code != 0)
        verbose(2, "compile_c_to_so: compile error: %d", exit_code);
    return exit_code == 0;
}
#else /* _MSC_VER */

/* The function producing the pre-compiled header. */
static void
make_pch(void)
{
    int exit_code;
    const char *rest_args[] = {
# ifdef __clang__
        "-emit-pch",
# endif
        "-o", NULL, NULL,
        NULL,
    };
    char **args;
    int len = sizeof(rest_args) / sizeof(const char *);

    rest_args[len - 2] = mjit_header_file;
    rest_args[len - 3] = mjit_pch_file;
    verbose(2, "Creating precompiled header");
    args = form_args(3, CC_COMMON_ARGS, CC_CODEFLAG_ARGS, rest_args);
    if (args == NULL) {
        if (mjit_opts.warnings || mjit_opts.verbose)
            fprintf(stderr, "MJIT warning: making precompiled header failed on forming args\n");
        CRITICAL_SECTION_START(3, "in make_pch");
        mjit_pch_status = PCH_FAILED;
        CRITICAL_SECTION_FINISH(3, "in make_pch");
        return;
    }

    exit_code = exec_process(mjit_cc_path, args);
    free(args);

    CRITICAL_SECTION_START(3, "in make_pch");
    if (exit_code == 0) {
        mjit_pch_status = PCH_SUCCESS;
    } else {
        if (mjit_opts.warnings || mjit_opts.verbose)
            fprintf(stderr, "MJIT warning: Making precompiled header failed on compilation. Stopping MJIT worker...\n");
        mjit_pch_status = PCH_FAILED;
    }
    /* wakeup `mjit_finish` */
    rb_native_cond_broadcast(&mjit_pch_wakeup);
    CRITICAL_SECTION_FINISH(3, "in make_pch");
}

/* Compile .c file to .o file. It returns 1 if it succeeds. (non-mswin) */
static int
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
    files[4] = mjit_pch_file;
# endif
    args = form_args(5, CC_COMMON_ARGS, CC_CODEFLAG_ARGS, files, CC_LIBS, CC_DLDFLAGS_ARGS);
    if (args == NULL)
        return FALSE;

    exit_code = exec_process(mjit_cc_path, args);
    free(args);

    if (exit_code != 0)
        verbose(2, "compile_c_to_o: compile error: %d", exit_code);
    return exit_code == 0;
}

/* Link .o files to .so file. It returns 1 if it succeeds. (non-mswin) */
static int
link_o_to_so(const char **o_files, const char *so_file)
{
    int exit_code;
    const char *options[] = {
        "-o", NULL,
# ifdef _WIN32
        mjit_libruby_pathflag,
# endif
        NULL
    };
    char **args;

    options[1] = so_file;
    args = form_args(6, CC_LDSHARED_ARGS, CC_CODEFLAG_ARGS,
                     options, o_files, CC_LIBS, CC_DLDFLAGS_ARGS);
    if (args == NULL)
        return FALSE;

    exit_code = exec_process(mjit_cc_path, args);
    free(args);

    if (exit_code != 0)
        verbose(2, "link_o_to_so: link error: %d", exit_code);
    return exit_code == 0;
}

/* Link all cached .o files and build a .so file. Reload all JIT func from it. This
   allows to avoid JIT code fragmentation and improve performance to call JIT-ed code.  */
static void
compact_all_jit_code(void)
{
# ifndef _WIN32 /* This requires header transformation but we don't transform header on Windows for now */
    struct rb_mjit_unit *unit;
    struct rb_mjit_unit_node *node;
    double start_time, end_time;
    static const char so_ext[] = DLEXT;
    char so_file[MAXPATHLEN];
    const char **o_files;
    int i = 0, success;

    /* Abnormal use case of rb_mjit_unit that doesn't have ISeq */
    unit = (struct rb_mjit_unit *)calloc(1, sizeof(struct rb_mjit_unit)); /* To prevent GC, don't use ZALLOC */
    if (unit == NULL) return;
    unit->id = mjit_current_unit_num++;
    sprint_uniq_filename(so_file, (int)sizeof(so_file), unit->id, MJIT_TMP_PREFIX, so_ext);

    /* NULL-ending for form_args */
    o_files = (const char **)alloca(sizeof(char *) * (mjit_active_units.length + 1));
    o_files[mjit_active_units.length] = NULL;
    CRITICAL_SECTION_START(3, "in compact_all_jit_code to keep .o files");
    for (node = mjit_active_units.head; node != NULL; node = node->next) {
        o_files[i] = node->unit->o_file;
        i++;
    }

    start_time = real_ms_time();
    success = link_o_to_so(o_files, so_file);
    end_time = real_ms_time();

    /* TODO: Shrink this big critical section. For now, this is needed to prevent failure by missing .o files.
       This assumes that o -> so link doesn't take long time because the bottleneck, which is compiler optimization,
       is already done. But actually it takes about 500ms for 5,000 methods on my Linux machine, so it's better to
       finish this critical section before link_o_to_so by disabling unload_units. */
    CRITICAL_SECTION_FINISH(3, "in compact_all_jit_code to keep .o files");

    if (success) {
        void *handle = dlopen(so_file, RTLD_NOW);
        if (handle == NULL) {
            if (mjit_opts.warnings || mjit_opts.verbose)
                fprintf(stderr, "MJIT warning: failure in loading code from compacted '%s': %s\n", so_file, dlerror());
            free(unit);
            return;
        }
        unit->handle = handle;

        /* lazily dlclose handle (and .so file for win32) on `mjit_finish()`. */
        node = (struct rb_mjit_unit_node *)calloc(1, sizeof(struct rb_mjit_unit_node)); /* To prevent GC, don't use ZALLOC */
        node->unit = unit;
        add_to_list(node, &mjit_compact_units);

        if (!mjit_opts.save_temps) {
#  ifdef _WIN32
            unit->so_file = strdup(so_file); /* lazily delete on `clean_object_files()` */
#  else
            remove_file(so_file);
#  endif
        }

        CRITICAL_SECTION_START(3, "in compact_all_jit_code to read list");
        for (node = mjit_active_units.head; node != NULL; node = node->next) {
            void *func;
            char funcname[35]; /* TODO: reconsider `35` */
            sprintf(funcname, "_mjit%d", node->unit->id);

            if ((func = dlsym(handle, funcname)) == NULL) {
                if (mjit_opts.warnings || mjit_opts.verbose)
                    fprintf(stderr, "MJIT warning: skipping to reload '%s' from '%s': %s\n", funcname, so_file, dlerror());
                continue;
            }

            if (node->unit->iseq) { /* Check whether GCed or not */
                /* Usage of jit_code might be not in a critical section.  */
                MJIT_ATOMIC_SET(node->unit->iseq->body->jit_func, (mjit_func_t)func);
            }
        }
        CRITICAL_SECTION_FINISH(3, "in compact_all_jit_code to read list");
        verbose(1, "JIT compaction (%.1fms): Compacted %d methods -> %s", end_time - start_time, mjit_active_units.length, so_file);
    }
    else {
        free(unit);
        verbose(1, "JIT compaction failure (%.1fms): Failed to compact methods", end_time - start_time);
    }
# endif /* _WIN32 */
}

#endif /* _MSC_VER */

static void *
load_func_from_so(const char *so_file, const char *funcname, struct rb_mjit_unit *unit)
{
    void *handle, *func;

    handle = dlopen(so_file, RTLD_NOW);
    if (handle == NULL) {
        if (mjit_opts.warnings || mjit_opts.verbose)
            fprintf(stderr, "MJIT warning: failure in loading code from '%s': %s\n", so_file, dlerror());
        return (void *)NOT_ADDED_JIT_ISEQ_FUNC;
    }

    func = dlsym(handle, funcname);
    unit->handle = handle;
    return func;
}

static void
print_jit_result(const char *result, const struct rb_mjit_unit *unit, const double duration, const char *c_file)
{
    verbose(1, "JIT %s (%.1fms): %s@%s:%d -> %s", result,
            duration, RSTRING_PTR(unit->iseq->body->location.label),
            RSTRING_PTR(rb_iseq_path(unit->iseq)), FIX2INT(unit->iseq->body->location.first_lineno), c_file);
}

#ifndef __clang__
static const char *
header_name_end(const char *s)
{
    const char *e = s + strlen(s);
# ifdef __GNUC__ /* don't chomp .pch for mswin */
    static const char suffix[] = ".gch";

    /* chomp .gch suffix */
    if (e > s+sizeof(suffix)-1 && strcmp(e-sizeof(suffix)+1, suffix) == 0) {
        e -= sizeof(suffix)-1;
    }
# endif
    return e;
}
#endif

/* Print platform-specific prerequisites in generated code. */
static void
compile_prelude(FILE *f)
{
#ifndef __clang__ /* -include-pch is used for Clang */
    const char *s = mjit_pch_file;
    const char *e = header_name_end(s);

    fprintf(f, "#include \"");
    /* print mjit_pch_file except .gch for gcc, but keep .pch for mswin */
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

/* Compile ISeq in UNIT and return function pointer of JIT-ed code.
   It may return NOT_COMPILED_JIT_ISEQ_FUNC if something went wrong. */
static mjit_func_t
convert_unit_to_func(struct rb_mjit_unit *unit)
{
    char c_file_buff[MAXPATHLEN], *c_file = c_file_buff, *so_file, funcname[35]; /* TODO: reconsider `35` */
    int success;
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

    /* print #include of MJIT header, etc. */
    compile_prelude(f);

    /* wait until mjit_gc_finish_hook is called */
    CRITICAL_SECTION_START(3, "before mjit_compile to wait GC finish");
    while (mjit_in_gc) {
        verbose(3, "Waiting wakeup from GC");
        rb_native_cond_wait(&mjit_gc_wakeup, &mjit_engine_mutex);
    }
    mjit_in_jit = TRUE;
    CRITICAL_SECTION_FINISH(3, "before mjit_compile to wait GC finish");

    {
        VALUE s = rb_iseq_path(unit->iseq);
        const char *label = RSTRING_PTR(unit->iseq->body->location.label);
        const char *path = RSTRING_PTR(s);
        int lineno = FIX2INT(unit->iseq->body->location.first_lineno);
        verbose(2, "start compilation: %s@%s:%d -> %s", label, path, lineno, c_file);
        fprintf(f, "/* %s@%s:%d */\n\n", label, path, lineno);
    }
    success = mjit_compile(f, unit->iseq->body, funcname);

    /* release blocking mjit_gc_start_hook */
    CRITICAL_SECTION_START(3, "after mjit_compile to wakeup client for GC");
    mjit_in_jit = FALSE;
    verbose(3, "Sending wakeup signal to client in a mjit-worker for GC");
    rb_native_cond_signal(&mjit_client_wakeup);
    CRITICAL_SECTION_FINISH(3, "in worker to wakeup client for GC");

    fclose(f);
    if (!success) {
        if (!mjit_opts.save_temps)
            remove_file(c_file);
        print_jit_result("failure", unit, 0, c_file);
        return (mjit_func_t)NOT_COMPILED_JIT_ISEQ_FUNC;
    }

    start_time = real_ms_time();
#ifdef _MSC_VER
    success = compile_c_to_so(c_file, so_file);
#else
    /* splitting .c -> .o step and .o -> .so step, to cache .o files in the future */
    if (success = compile_c_to_o(c_file, o_file)) {
        const char *o_files[2] = { NULL, NULL };
        o_files[0] = o_file;
        success = link_o_to_so(o_files, so_file);

        /* Alwasy set o_file for compaction. The value is also used for lazy deletion. */
        unit->o_file = strdup(o_file);
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
    if (!mjit_opts.save_temps) {
#ifdef _WIN32
        unit->so_file = strdup(so_file); /* lazily delete on `clean_object_files()` */
#else
        remove_file(so_file);
#endif
    }

    if ((uintptr_t)func > (uintptr_t)LAST_JIT_ISEQ_FUNC) {
        struct rb_mjit_unit_node *node = create_list_node(unit);
        CRITICAL_SECTION_START(3, "end of jit");
        add_to_list(node, &mjit_active_units);
        if (unit->iseq)
            print_jit_result("success", unit, end_time - start_time, c_file);
        CRITICAL_SECTION_FINISH(3, "end of jit");
    }
    return (mjit_func_t)func;
}

/* Set to TRUE to stop worker.  */
int mjit_stop_worker_p;
/* Set to TRUE if worker is stopped.  */
int mjit_worker_stopped;

/* The function implementing a worker. It is executed in a separate
   thread by rb_thread_create_mjit_thread. It compiles precompiled header
   and then compiles requested ISeqs. */
void
mjit_worker(void)
{
#ifndef _MSC_VER
    if (mjit_pch_status == PCH_NOT_READY) {
        make_pch();
    }
#endif
    if (mjit_pch_status == PCH_FAILED) {
        mjit_enabled = FALSE;
        CRITICAL_SECTION_START(3, "in worker to update mjit_worker_stopped");
        mjit_worker_stopped = TRUE;
        verbose(3, "Sending wakeup signal to client in a mjit-worker");
        rb_native_cond_signal(&mjit_client_wakeup);
        CRITICAL_SECTION_FINISH(3, "in worker to update mjit_worker_stopped");
        return; /* TODO: do the same thing in the latter half of mjit_finish */
    }

    /* main worker loop */
    while (!mjit_stop_worker_p) {
        struct rb_mjit_unit_node *node;

        /* wait until unit is available */
        CRITICAL_SECTION_START(3, "in worker dequeue");
        while ((mjit_unit_queue.head == NULL || mjit_active_units.length > mjit_opts.max_cache_size) && !mjit_stop_worker_p) {
            rb_native_cond_wait(&mjit_worker_wakeup, &mjit_engine_mutex);
            verbose(3, "Getting wakeup from client");
        }
        node = get_from_list(&mjit_unit_queue);
        CRITICAL_SECTION_FINISH(3, "in worker dequeue");

        if (node) {
            mjit_func_t func = convert_unit_to_func(node->unit);

            CRITICAL_SECTION_START(3, "in jit func replace");
            if (node->unit->iseq) { /* Check whether GCed or not */
                /* Usage of jit_code might be not in a critical section.  */
                MJIT_ATOMIC_SET(node->unit->iseq->body->jit_func, func);
            }
            remove_from_list(node, &mjit_unit_queue);
            CRITICAL_SECTION_FINISH(3, "in jit func replace");

#ifndef _MSC_VER
            /* Combine .o files to one .so and reload all jit_func to improve memory locality */
            if ((!mjit_opts.wait && mjit_unit_queue.length == 0 && mjit_active_units.length > 1)
                || mjit_active_units.length == mjit_opts.max_cache_size) {
                compact_all_jit_code();
            }
#endif
        }
    }

    /* To keep mutex unlocked when it is destroyed by mjit_finish, don't wrap CRITICAL_SECTION here. */
    mjit_worker_stopped = TRUE;
}
