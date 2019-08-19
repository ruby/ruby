/**********************************************************************

  mjit.c - Infrastructure for MRI method JIT compiler

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


   We don't use SIGCHLD signal and WNOHANG waitpid in MJIT as it
   might mess with ruby code dealing with signals.  Also as SIGCHLD
   signal can be delivered to non-main thread, the stack might have a
   constraint.  So the correct version of code based on SIGCHLD and
   WNOHANG waitpid would be very complicated.  */

#ifdef __sun
#define __EXTENSIONS__ 1
#endif

#include "internal.h"
#include "vm_core.h"
#include "mjit.h"
#include "gc.h"
#include "constant.h"
#include "id_table.h"
#include "ruby_assert.h"
#include "ruby/util.h"
#include "ruby/version.h"

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

extern void rb_native_mutex_lock(rb_nativethread_lock_t *lock);
extern void rb_native_mutex_unlock(rb_nativethread_lock_t *lock);
extern void rb_native_mutex_initialize(rb_nativethread_lock_t *lock);
extern void rb_native_mutex_destroy(rb_nativethread_lock_t *lock);

extern void rb_native_cond_initialize(rb_nativethread_cond_t *cond);
extern void rb_native_cond_destroy(rb_nativethread_cond_t *cond);
extern void rb_native_cond_signal(rb_nativethread_cond_t *cond);
extern void rb_native_cond_broadcast(rb_nativethread_cond_t *cond);
extern void rb_native_cond_wait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex);

extern int rb_thread_create_mjit_thread(void (*child_hook)(void), void (*worker_func)(void));

#define RB_CONDATTR_CLOCK_MONOTONIC 1

#ifdef _WIN32
#define dlopen(name,flag) ((void*)LoadLibrary(name))
#define dlerror() strerror(rb_w32_map_errno(GetLastError()))
#define dlsym(handle,name) ((void*)GetProcAddress((handle),(name)))
#define dlclose(handle) (FreeLibrary(handle))
#define RTLD_NOW  -1

#define waitpid(pid,stat_loc,options) (WaitForSingleObject((HANDLE)(pid), INFINITE), GetExitCodeProcess((HANDLE)(pid), (LPDWORD)(stat_loc)))
#define WIFEXITED(S) ((S) != STILL_ACTIVE)
#define WEXITSTATUS(S) (S)
#define WIFSIGNALED(S) (0)
typedef intptr_t pid_t;
#endif

/* Atomically set function pointer if possible. */
#ifdef _WIN32
# ifdef InterlockedExchangePointer
#  define MJIT_ATOMIC_SET(var, val) InterlockedExchangePointer((void **)&(var), (void *)val)
# else
#  define MJIT_ATOMIC_SET(var, val) (void)((var) = (val))
# endif
#else
# define MJIT_ATOMIC_SET(var, val) ATOMIC_SET(var, val)
#endif

/* A copy of MJIT portion of MRI options since MJIT initialization.  We
   need them as MJIT threads still can work when the most MRI data were
   freed. */
struct mjit_options mjit_opts;

/* The unit structure that holds metadata of ISeq for MJIT.  */
struct rb_mjit_unit {
    /* Unique order number of unit.  */
    int id;
    /* Dlopen handle of the loaded object file.  */
    void *handle;
    const rb_iseq_t *iseq;
#ifdef _WIN32
    /* DLL cannot be removed while loaded on Windows */
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

/* TRUE if MJIT is initialized and will be used.  */
int mjit_init_p = FALSE;

/* Priority queue of iseqs waiting for JIT compilation.
   This variable is a pointer to head unit of the queue. */
static struct rb_mjit_unit_list unit_queue;
/* List of units which are successfully compiled. */
static struct rb_mjit_unit_list active_units;
/* The number of so far processed ISEQs, used to generate unique id.  */
static int current_unit_num;
/* A mutex for conitionals and critical sections.  */
static rb_nativethread_lock_t mjit_engine_mutex;
/* A thread conditional to wake up `mjit_finish` at the end of PCH thread.  */
static rb_nativethread_cond_t mjit_pch_wakeup;
/* A thread conditional to wake up the client if there is a change in
   executed unit status.  */
static rb_nativethread_cond_t mjit_client_wakeup;
/* A thread conditional to wake up a worker if there we have something
   to add or we need to stop MJIT engine.  */
static rb_nativethread_cond_t mjit_worker_wakeup;
/* A thread conditional to wake up workers if at the end of GC.  */
static rb_nativethread_cond_t mjit_gc_wakeup;
/* True when GC is working.  */
static int in_gc;
/* True when JIT is working.  */
static int in_jit;

/* Defined in the client thread before starting MJIT threads:  */
/* Used C compiler path.  */
static const char *cc_path;
/* Name of the header file.  */
static char *header_file;
/* Name of the precompiled header file.  */
static char *pch_file;
/* Path of "/tmp", which can be changed to $TMP in MinGW. */
static char *tmp_dir;
/* Hash like { 1 => true, 2 => true, ... } whose keys are valid `class_serial`s.
   This is used to invalidate obsoleted CALL_CACHE. */
static VALUE valid_class_serials;
/* Ruby level interface module.  */
VALUE rb_mMJIT;

#ifdef _WIN32
/* Linker option to enable libruby. */
static char *libruby_pathflag;
#endif

static void remove_file(const char *filename);

/* Return time in milliseconds as a double.  */
#ifdef __APPLE__
double ruby_real_ms_time(void);
#define real_ms_time() ruby_real_ms_time()
#else
static double
real_ms_time(void)
{
#ifdef HAVE_CLOCK_GETTIME
    struct timespec  tv;
# ifdef CLOCK_MONOTONIC
    const clockid_t c = CLOCK_MONOTONIC;
# else
    const clockid_t c = CLOCK_REALTIME;
# endif

    clock_gettime(c, &tv);
    return tv.tv_nsec / 1000000.0 + tv.tv_sec * 1000.0;
#else
    struct timeval  tv;

    gettimeofday(&tv, NULL);
    return tv.tv_usec / 1000.0 + tv.tv_sec * 1000.0;
#endif
}
#endif

/* Make and return copy of STR in the heap. */
#define get_string ruby_strdup

static int
sprint_uniq_filename(char *str, size_t size, unsigned long id, const char *prefix, const char *suffix)
{
    return snprintf(str, size, "%s/%sp%luu%lu%s", tmp_dir, prefix, (unsigned long) getpid(), id, suffix);
}

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
    char **args, **res;

    va_start(argp, num);
    res = NULL;
    for (i = len = 0; i < num; i++) {
        args = va_arg(argp, char **);
        n = args_len(args);
        REALLOC_N(res, char *, len + n + 1);
        MEMCPY(res + len, args, char *, n + 1);
        len += n;
    }
    va_end(argp);
    return res;
}

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
        /* Not calling IO functions between fork and exec for safety */
        int dev_null = rb_cloexec_open(ruby_null_device, O_WRONLY, 0);

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
            pid = execvp(path, argv); /* Pid will be negative on an error */
            /* Even if we successfully found CC to compile PCH we still can
             fail with loading the CC in very rare cases for some reasons.
             Stop the forked process in this case.  */
            verbose(1, "MJIT: Error in execvp: %s\n", path);
            _exit(1);
        }
        (void)close(dev_null);
    }
#endif
    return pid;
}

/* Execute an OS process of executable PATH with arguments ARGV.
   Return -1 or -2 if failed to execute, otherwise exit code of the process.
   TODO: Use the same function in process.c */
static int
exec_process(const char *path, char *const argv[])
{
    int stat, exit_code;
    pid_t pid;

    pid = start_process(path, argv);
    if (pid <= 0)
        return -2;

    for (;;) {
        waitpid(pid, &stat, 0);
        if (WIFEXITED(stat)) {
            exit_code = WEXITSTATUS(stat);
            break;
        } else if (WIFSIGNALED(stat)) {
            exit_code = -1;
            break;
        }
    }
    return exit_code;
}

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

/* Wait until workers don't compile any iseq.  It is called at the
   start of GC.  */
void
mjit_gc_start_hook(void)
{
    if (!mjit_init_p)
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
    if (!mjit_init_p)
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
    if (!mjit_init_p)
        return;
    CRITICAL_SECTION_START(4, "mjit_free_iseq");
    if (iseq->body->jit_unit) {
        /* jit_unit is not freed here because it may be referred by multiple
           lists of units. `get_from_list` and `mjit_finish` do the job. */
        iseq->body->jit_unit->iseq = NULL;
    }
    CRITICAL_SECTION_FINISH(4, "mjit_free_iseq");
}

static void
clean_so_file(struct rb_mjit_unit *unit)
{
#ifdef _WIN32
    char *so_file = unit->so_file;
    if (so_file) {
        unit->so_file = NULL;
        remove_file(so_file);
        free(so_file);
    }
#endif
}

static void
free_unit(struct rb_mjit_unit *unit)
{
    if (unit->iseq) /* ISeq is not GCed */
        unit->iseq->body->jit_func = 0;
    if (unit->handle) /* handle is NULL if it's in queue */
        dlclose(unit->handle);
    clean_so_file(unit);
    xfree(unit);
}

static void
init_list(struct rb_mjit_unit_list *list)
{
    list->head = NULL;
    list->length = 0;
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

/* Free unit list. This should be called only when worker is finished
   because node of unit_queue and one of active_units may have the same unit
   during proceeding unit. */
static void
free_list(struct rb_mjit_unit_list *list)
{
    struct rb_mjit_unit_node *node, *next;
    for (node = list->head; node != NULL; node = next) {
        next = node->next;
        free_unit(node->unit);
        xfree(node);
    }
}

#include "mjit_config.h"

static const char *const CC_DEBUG_ARGS[] = {MJIT_DEBUGFLAGS NULL};
static const char *const CC_OPTIMIZE_ARGS[] = {MJIT_OPTFLAGS NULL};

#if defined __GNUC__ && !defined __clang__
#define GCC_PIC_FLAGS "-Wfatal-errors", "-fPIC", "-shared", "-w", \
    "-pipe",
#else
#define GCC_PIC_FLAGS /* empty */
#endif

static const char *const CC_COMMON_ARGS[] = {
    MJIT_CC_COMMON MJIT_CFLAGS GCC_PIC_FLAGS
    NULL
};

static const char *const CC_LDSHARED_ARGS[] = {MJIT_LDSHARED GCC_PIC_FLAGS NULL};
static const char *const CC_DLDFLAGS_ARGS[] = {
    MJIT_DLDFLAGS
#if defined __GNUC__ && !defined __clang__
    "-nostartfiles",
# ifndef _WIN32
    "-nodefaultlibs", "-nostdlib",
# endif
#endif
    NULL
};

static const char *const CC_LIBS[] = {
#ifdef _WIN32
    MJIT_LIBS
# if defined __GNUC__ && !defined __clang__
    "-lmsvcrt",
    "-lgcc",
# endif
#endif
    NULL
};

#define CC_CODEFLAG_ARGS (mjit_opts.debug ? CC_DEBUG_ARGS : CC_OPTIMIZE_ARGS)
/* Status of the precompiled header creation.  The status is
   shared by the workers and the pch thread.  */
static enum {PCH_NOT_READY, PCH_FAILED, PCH_SUCCESS} pch_status;

/* The function producing the pre-compiled header. */
static void
make_pch(void)
{
    int exit_code;
#ifdef _MSC_VER
    /* XXX TODO */
    exit_code = 0;
#else
    const char *rest_args[] = {
# ifdef __clang__
        "-emit-pch",
# endif
        "-o", NULL, NULL,
        NULL,
    };
    char **args;
    int len = sizeof(rest_args) / sizeof(const char *);

    rest_args[len - 2] = header_file;
    rest_args[len - 3] = pch_file;
    verbose(2, "Creating precompiled header");
    args = form_args(3, CC_COMMON_ARGS, CC_CODEFLAG_ARGS, rest_args);
    if (args == NULL) {
        if (mjit_opts.warnings || mjit_opts.verbose)
            fprintf(stderr, "MJIT warning: making precompiled header failed on forming args\n");
        CRITICAL_SECTION_START(3, "in make_pch");
        pch_status = PCH_FAILED;
        CRITICAL_SECTION_FINISH(3, "in make_pch");
        return;
    }

    exit_code = exec_process(cc_path, args);
    xfree(args);
#endif

    CRITICAL_SECTION_START(3, "in make_pch");
    if (exit_code == 0) {
        pch_status = PCH_SUCCESS;
    } else {
        if (mjit_opts.warnings || mjit_opts.verbose)
            fprintf(stderr, "MJIT warning: Making precompiled header failed on compilation. Stopping MJIT worker...\n");
        pch_status = PCH_FAILED;
    }
    /* wakeup `mjit_finish` */
    rb_native_cond_broadcast(&mjit_pch_wakeup);
    CRITICAL_SECTION_FINISH(3, "in make_pch");
}

#define append_str2(p, str, len) ((char *)memcpy((p), str, (len))+(len))
#define append_str(p, str) append_str2(p, str, sizeof(str)-1)
#define append_lit(p, str) append_str2(p, str, rb_strlen_lit(str))

/* Compile C file to so. It returns 1 if it succeeds. */
static int
compile_c_to_so(const char *c_file, const char *so_file)
{
    int exit_code;
    const char *files[] = {
#ifndef _MSC_VER
        "-o",
#endif
        NULL, NULL,
#ifdef __clang__
        "-include-pch", NULL,
#endif
#ifdef _WIN32
# ifdef _MSC_VER
        "-link",
# endif
        libruby_pathflag,
#endif
        NULL,
    };
    char **args;
#ifdef _MSC_VER
    char *p;
    int solen;
#endif

#ifdef _MSC_VER
    solen = strlen(so_file);
    files[0] = p = xmalloc(rb_strlen_lit("-Fe") + solen + 1);
    p = append_lit(p, "-Fe");
    p = append_str2(p, so_file, solen);
    *p = '\0';
    files[1] = c_file;
#else
# ifdef __clang__
    files[4] = pch_file;
# endif
    files[2] = c_file;
    files[1] = so_file;
#endif
    args = form_args(5, CC_LDSHARED_ARGS, CC_CODEFLAG_ARGS,
                     files, CC_LIBS, CC_DLDFLAGS_ARGS);
    if (args == NULL)
        return FALSE;

    exit_code = exec_process(cc_path, args);
    xfree(args);
#ifdef _MSC_VER
    xfree((char *)files[0]);
#endif

    if (exit_code != 0)
        verbose(2, "compile_c_to_so: compile error: %d", exit_code);
    return exit_code == 0;
}

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

#define MJIT_TMP_PREFIX "_ruby_mjit_"

#ifndef __clang__
static const char *
header_name_end(const char *s)
{
    const char *e = s + strlen(s);
#ifdef __GNUC__
    static const char suffix[] = ".gch";

    /* chomp .gch suffix */
    if (e > s+sizeof(suffix)-1 && strcmp(e-sizeof(suffix)+1, suffix) == 0) {
        e -= sizeof(suffix)-1;
    }
#endif
    return e;
}
#endif

static void
print_jit_result(const char *result, const struct rb_mjit_unit *unit, const double duration, const char *c_file)
{
    verbose(1, "JIT %s (%.1fms): %s@%s:%d -> %s", result,
            duration, RSTRING_PTR(unit->iseq->body->location.label),
            RSTRING_PTR(rb_iseq_path(unit->iseq)), FIX2INT(unit->iseq->body->location.first_lineno), c_file);
}

static void
remove_file(const char *filename)
{
    if (remove(filename) && (mjit_opts.warnings || mjit_opts.verbose)) {
        fprintf(stderr, "MJIT warning: failed to remove \"%s\": %s\n",
                filename, strerror(errno));
    }
}

/* Compile ISeq in UNIT and return function pointer of JIT-ed code.
   It may return NOT_COMPILABLE_JIT_ISEQ_FUNC if something went wrong. */
static mjit_func_t
convert_unit_to_func(struct rb_mjit_unit *unit)
{
    char c_file_buff[70], *c_file = c_file_buff, *so_file, funcname[35];
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

    c_file_len = sprint_uniq_filename(c_file_buff, c_file_len, unit->id, MJIT_TMP_PREFIX, c_ext);
    if (c_file_len >= (int)sizeof(c_file_buff)) {
        ++c_file_len;
        c_file = alloca(c_file_len);
        c_file_len = sprint_uniq_filename(c_file, c_file_len, unit->id, MJIT_TMP_PREFIX, c_ext);
    }
    ++c_file_len;
    so_file = alloca(c_file_len - sizeof(c_ext) + sizeof(so_ext));
    memcpy(so_file, c_file, c_file_len - sizeof(c_ext));
    memcpy(&so_file[c_file_len - sizeof(c_ext)], so_ext, sizeof(so_ext));
    sprintf(funcname, "_mjit%d", unit->id);

    fd = rb_cloexec_open(c_file, access_mode, 0600);
    if (fd < 0 || (f = fdopen(fd, "w")) == NULL) {
        int e = errno;
        if (fd >= 0) (void)close(fd);
        verbose(1, "Failed to fopen '%s', giving up JIT for it (%s)", c_file, strerror(e));
        return (mjit_func_t)NOT_COMPILABLE_JIT_ISEQ_FUNC;
    }

#ifdef __clang__
    /* -include-pch is used for Clang */
#else
    {
# ifdef __GNUC__
        const char *s = pch_file;
# else
        const char *s = header_file;
# endif
        const char *e = header_name_end(s);

        fprintf(f, "#include \"");
        /* print pch_file except .gch */
        for (; s < e; s++) {
            switch(*s) {
              case '\\': case '"':
                fputc('\\', f);
            }
            fputc(*s, f);
        }
        fprintf(f, "\"\n");
    }
#endif

#ifdef _WIN32
    fprintf(f, "void _pei386_runtime_relocator(void){}\n");
    fprintf(f, "int __stdcall DllMainCRTStartup(void* hinstDLL, unsigned int fdwReason, void* lpvReserved) { return 1; }\n");
#endif

    /* wait until mjit_gc_finish_hook is called */
    CRITICAL_SECTION_START(3, "before mjit_compile to wait GC finish");
    while (in_gc) {
        verbose(3, "Waiting wakeup from GC");
        rb_native_cond_wait(&mjit_gc_wakeup, &mjit_engine_mutex);
    }
    in_jit = TRUE;
    CRITICAL_SECTION_FINISH(3, "before mjit_compile to wait GC finish");

    {
        VALUE s = rb_iseq_path(unit->iseq);
        const char *label = RSTRING_PTR(unit->iseq->body->location.label);
        const char *path = RSTRING_PTR(s);
        int lineno = FIX2INT(unit->iseq->body->location.first_lineno);
        verbose(2, "start compile: %s@%s:%d -> %s", label, path, lineno, c_file);
        fprintf(f, "/* %s@%s:%d */\n\n", label, path, lineno);
    }
    success = mjit_compile(f, unit->iseq->body, funcname);

    /* release blocking mjit_gc_start_hook */
    CRITICAL_SECTION_START(3, "after mjit_compile to wakeup client for GC");
    in_jit = FALSE;
    verbose(3, "Sending wakeup signal to client in a mjit-worker for GC");
    rb_native_cond_signal(&mjit_client_wakeup);
    CRITICAL_SECTION_FINISH(3, "in worker to wakeup client for GC");

    fclose(f);
    if (!success) {
        if (!mjit_opts.save_temps)
            remove_file(c_file);
        print_jit_result("failure", unit, 0, c_file);
        return (mjit_func_t)NOT_COMPILABLE_JIT_ISEQ_FUNC;
    }

    start_time = real_ms_time();
    success = compile_c_to_so(c_file, so_file);
    end_time = real_ms_time();

    if (!mjit_opts.save_temps)
        remove_file(c_file);
    if (!success) {
        verbose(2, "Failed to generate so: %s", so_file);
        return (mjit_func_t)NOT_COMPILABLE_JIT_ISEQ_FUNC;
    }

    func = load_func_from_so(so_file, funcname, unit);
    if (!mjit_opts.save_temps) {
#ifdef _WIN32
        unit->so_file = strdup(so_file);
#else
        remove_file(so_file);
#endif
    }

    if ((ptrdiff_t)func > (ptrdiff_t)LAST_JIT_ISEQ_FUNC) {
        struct rb_mjit_unit_node *node = create_list_node(unit);
        CRITICAL_SECTION_START(3, "end of jit");
        add_to_list(node, &active_units);
        if (unit->iseq)
            print_jit_result("success", unit, end_time - start_time, c_file);
        CRITICAL_SECTION_FINISH(3, "end of jit");
    }
    return (mjit_func_t)func;
}

/* Set to TRUE to stop worker.  */
static int stop_worker_p;
/* Set to TRUE if worker is stopped.  */
static int worker_stopped;

/* The function implementing a worker. It is executed in a separate
   thread by rb_thread_create_mjit_thread. It compiles precompiled header
   and then compiles requested ISeqs. */
static void
worker(void)
{
    make_pch();
    if (pch_status == PCH_FAILED) {
        mjit_init_p = FALSE;
        CRITICAL_SECTION_START(3, "in worker to update worker_stopped");
        worker_stopped = TRUE;
        verbose(3, "Sending wakeup signal to client in a mjit-worker");
        rb_native_cond_signal(&mjit_client_wakeup);
        CRITICAL_SECTION_FINISH(3, "in worker to update worker_stopped");
        return; /* TODO: do the same thing in the latter half of mjit_finish */
    }

    /* main worker loop */
    while (!stop_worker_p) {
        struct rb_mjit_unit_node *node;

        /* wait until unit is available */
        CRITICAL_SECTION_START(3, "in worker dequeue");
        while ((unit_queue.head == NULL || active_units.length > mjit_opts.max_cache_size) && !stop_worker_p) {
            rb_native_cond_wait(&mjit_worker_wakeup, &mjit_engine_mutex);
            verbose(3, "Getting wakeup from client");
        }
        node = get_from_list(&unit_queue);
        CRITICAL_SECTION_FINISH(3, "in worker dequeue");

        if (node) {
            mjit_func_t func = convert_unit_to_func(node->unit);

            CRITICAL_SECTION_START(3, "in jit func replace");
            if (node->unit->iseq) { /* Check whether GCed or not */
                /* Usage of jit_code might be not in a critical section.  */
                MJIT_ATOMIC_SET(node->unit->iseq->body->jit_func, func);
            }
            remove_from_list(node, &unit_queue);
            CRITICAL_SECTION_FINISH(3, "in jit func replace");
        }
    }

    /* To keep mutex unlocked when it is destroyed by mjit_finish, don't wrap CRITICAL_SECTION here. */
    worker_stopped = TRUE;
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
    const rb_iseq_t *iseq;
    const rb_control_frame_t *cfp;
    rb_control_frame_t *last_cfp = ec->cfp;
    const rb_control_frame_t *end_marker_cfp;
    ptrdiff_t i, size;

    if (ec->vm_stack == NULL)
        return;
    end_marker_cfp = RUBY_VM_END_CONTROL_FRAME(ec);
    size = end_marker_cfp - last_cfp;
    for (i = 0, cfp = end_marker_cfp - 1; i < size; i++, cfp = RUBY_VM_NEXT_CONTROL_FRAME(cfp)) {
        if (cfp->pc && (iseq = cfp->iseq) != NULL
            && imemo_type((VALUE) iseq) == imemo_iseq
            && (iseq->body->jit_unit) != NULL) {
            iseq->body->jit_unit->used_code_p = TRUE;
        }
    }
}

/* Unload JIT code of some units to satisfy the maximum permitted
   number of units with a loaded code.  */
static void
unload_units(void)
{
    rb_vm_t *vm = GET_THREAD()->vm;
    rb_thread_t *th = NULL;
    struct rb_mjit_unit_node *node, *next, *worst_node;
    struct rb_mjit_unit *unit;
    struct mjit_cont *cont;
    int delete_num, units_num = active_units.length;

    /* For now, we don't unload units when ISeq is GCed. We should
       unload such ISeqs first here. */
    for (node = active_units.head; node != NULL; node = next) {
        next = node->next;
        if (node->unit->iseq == NULL) { /* ISeq is GCed. */
            free_unit(node->unit);
            remove_from_list(node, &active_units);
        }
    }

    /* Detect units which are in use and can't be unloaded. */
    for (node = active_units.head; node != NULL; node = node->next) {
        assert(node->unit != NULL && node->unit->iseq != NULL && node->unit->handle != NULL);
        node->unit->used_code_p = FALSE;
    }
    list_for_each(&vm->living_threads, th, vmlt_node) {
        mark_ec_units(th->ec);
    }
    for (cont = first_cont; cont != NULL; cont = cont->next) {
        mark_ec_units(cont->ec);
    }

    /* Remove 1/10 units more to decrease unloading calls.  */
    delete_num = active_units.length / 10;
    for (; active_units.length > mjit_opts.max_cache_size - delete_num;) {
        /* Find one unit that has the minimum total_calls. */
        worst_node = NULL;
        for (node = active_units.head; node != NULL; node = node->next) {
            if (node->unit->used_code_p) /* We can't unload code on stack. */
                continue;

            if (worst_node == NULL || worst_node->unit->iseq->body->total_calls > node->unit->iseq->body->total_calls) {
                worst_node = node;
            }
        }
        if (worst_node == NULL)
            break;

        /* Unload the worst node. */
        verbose(2, "Unloading unit %d (calls=%lu)", worst_node->unit->id, worst_node->unit->iseq->body->total_calls);
        unit = worst_node->unit;
        unit->iseq->body->jit_func = (mjit_func_t)NOT_READY_JIT_ISEQ_FUNC;
        remove_from_list(worst_node, &active_units);

        assert(unit->handle != NULL);
        dlclose(unit->handle);
        unit->handle = NULL;
        clean_so_file(unit);
    }
    verbose(1, "Too many JIT code -- %d units unloaded", units_num - active_units.length);
}

/* Add ISEQ to be JITed in parallel with the current thread.
   Unload some JIT codes if there are too many of them.  */
void
mjit_add_iseq_to_process(const rb_iseq_t *iseq)
{
    struct rb_mjit_unit_node *node;

    if (!mjit_init_p || pch_status == PCH_FAILED)
        return;

    iseq->body->jit_func = (mjit_func_t)NOT_READY_JIT_ISEQ_FUNC;
    create_unit(iseq);
    if (iseq->body->jit_unit == NULL)
        /* Failure in creating the unit.  */
        return;

    node = create_list_node(iseq->body->jit_unit);
    CRITICAL_SECTION_START(3, "in add_iseq_to_process");
    add_to_list(node, &unit_queue);
    if (active_units.length >= mjit_opts.max_cache_size) {
        unload_units();
    }
    verbose(3, "Sending wakeup signal to workers in mjit_add_iseq_to_process");
    rb_native_cond_broadcast(&mjit_worker_wakeup);
    CRITICAL_SECTION_FINISH(3, "in add_iseq_to_process");
}

/* For this timeout seconds, --jit-wait will wait for JIT compilation finish. */
#define MJIT_WAIT_TIMEOUT_SECONDS 60

/* Wait for JIT compilation finish for --jit-wait. This should only return a function pointer
   or NOT_COMPILABLE_JIT_ISEQ_FUNC. */
mjit_func_t
mjit_get_iseq_func(struct rb_iseq_constant_body *body)
{
    struct timeval tv;
    int tries = 0;
    tv.tv_sec = 0;
    tv.tv_usec = 1000;
    while (body->jit_func == (mjit_func_t)NOT_READY_JIT_ISEQ_FUNC) {
        tries++;
        if (tries / 1000 > MJIT_WAIT_TIMEOUT_SECONDS || pch_status == PCH_FAILED) {
            CRITICAL_SECTION_START(3, "in mjit_get_iseq_func to set jit_func");
            body->jit_func = (mjit_func_t)NOT_COMPILABLE_JIT_ISEQ_FUNC; /* JIT worker seems dead. Give up. */
            CRITICAL_SECTION_FINISH(3, "in mjit_get_iseq_func to set jit_func");
            if (mjit_opts.warnings || mjit_opts.verbose)
                fprintf(stderr, "MJIT warning: timed out to wait for JIT finish\n");
            break;
        }

        CRITICAL_SECTION_START(3, "in mjit_get_iseq_func for a client wakeup");
        rb_native_cond_broadcast(&mjit_worker_wakeup);
        CRITICAL_SECTION_FINISH(3, "in mjit_get_iseq_func for a client wakeup");
        rb_thread_wait_for(tv);
    }
    return body->jit_func;
}

/* GCC and CLANG executable paths.  TODO: The paths should absolute
   ones to prevent changing C compiler for security reasons.  */
#define CC_PATH CC_COMMON_ARGS[0]

extern VALUE ruby_archlibdir_path, ruby_prefix_path;

static void
init_header_filename(void)
{
    int fd;
    /* Root path of the running ruby process. Equal to RbConfig::TOPDIR.  */
    VALUE basedir_val;
    char *basedir;
    size_t baselen;
    /* A name of the header file included in any C file generated by MJIT for iseqs. */
    static const char header_name[] = MJIT_MIN_HEADER_NAME;
    const size_t header_name_len = sizeof(header_name) - 1;
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

    basedir_val = ruby_prefix_path;
    basedir = StringValuePtr(basedir_val);
    baselen = RSTRING_LEN(basedir_val);

    header_file = xmalloc(baselen + header_name_len + 1);
    p = append_str2(header_file, basedir, baselen);
    p = append_str2(p, header_name, header_name_len + 1);
    if ((fd = rb_cloexec_open(header_file, O_RDONLY, 0)) < 0) {
        verbose(2, "Cannot access header file %s\n", header_file);
        xfree(header_file);
        header_file = NULL;
        return;
    }
    (void)close(fd);

#ifdef _WIN32
    basedir_val = ruby_archlibdir_path;
    basedir = StringValuePtr(basedir_val);
    baselen = RSTRING_LEN(basedir_val);
    libruby_pathflag = p = xmalloc(libpathflag_len + baselen + 1);
    p = append_str(p, libpathflag);
    p = append_str2(p, basedir, baselen);
    *p = '\0';
#endif
}

/* This is called after each fork in the child in to switch off MJIT
   engine in the child as it does not inherit MJIT threads.  */
static void
child_after_fork(void)
{
    verbose(3, "Switching off MJIT in a forked child");
    mjit_init_p = FALSE;
    /* TODO: Should we initiate MJIT in the forked Ruby.  */
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
    #ifndef MAXPATHLEN
    #define MAXPATHLEN 1024
    #endif
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
    if (check_tmpdir(tmpdir = getenv(name))) return get_string(tmpdir)
    RETURN_ENV("TMPDIR");
    RETURN_ENV("TMP");
    tmpdir = system_default_tmpdir();
    if (check_tmpdir(tmpdir)) return tmpdir;
    return get_string("/tmp");
# undef RETURN_ENV
}

/* Default permitted number of units with a JIT code kept in
   memory.  */
#define DEFAULT_CACHE_SIZE 1000
/* A default threshold used to add iseq to JIT. */
#define DEFAULT_MIN_CALLS_TO_ADD 5
/* Minimum value for JIT cache size.  */
#define MIN_CACHE_SIZE 10

extern const char ruby_description_with_jit[];

/* Initialize MJIT.  Start a thread creating the precompiled header and
   processing ISeqs.  The function should be called first for using MJIT.
   If everything is successfull, MJIT_INIT_P will be TRUE.  */
void
mjit_init(struct mjit_options *opts)
{
    VALUE rb_description;

    mjit_opts = *opts;
    mjit_init_p = TRUE;

    /* Normalize options */
    if (mjit_opts.min_calls == 0)
        mjit_opts.min_calls = DEFAULT_MIN_CALLS_TO_ADD;
    if (mjit_opts.max_cache_size <= 0)
        mjit_opts.max_cache_size = DEFAULT_CACHE_SIZE;
    if (mjit_opts.max_cache_size < MIN_CACHE_SIZE)
        mjit_opts.max_cache_size = MIN_CACHE_SIZE;

    verbose(2, "MJIT: CC defaults to %s", CC_PATH);

    /* Initialize variables for compilation */
    pch_status = PCH_NOT_READY;
    cc_path = CC_PATH;

    tmp_dir = system_tmpdir();
    verbose(2, "MJIT: tmp_dir is %s", tmp_dir);

    init_header_filename();
    pch_file = get_uniq_filename(0, MJIT_TMP_PREFIX "h", ".h.gch");
    if (header_file == NULL || pch_file == NULL) {
        mjit_init_p = FALSE;
        verbose(1, "Failure in MJIT header file name initialization\n");
        return;
    }

    init_list(&unit_queue);
    init_list(&active_units);

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

    /* Overwrites RUBY_DESCRIPTION constant */
    rb_const_remove(rb_cObject, rb_intern("RUBY_DESCRIPTION"));
    rb_description = rb_usascii_str_new_static(ruby_description_with_jit, strlen(ruby_description_with_jit));
    rb_define_global_const("RUBY_DESCRIPTION", rb_obj_freeze(rb_description));

    /* Initialize worker thread */
    stop_worker_p = FALSE;
    worker_stopped = FALSE;
    if (!rb_thread_create_mjit_thread(child_after_fork, worker)) {
        mjit_init_p = FALSE;
        rb_native_mutex_destroy(&mjit_engine_mutex);
        rb_native_cond_destroy(&mjit_pch_wakeup);
        rb_native_cond_destroy(&mjit_client_wakeup);
        rb_native_cond_destroy(&mjit_worker_wakeup);
        rb_native_cond_destroy(&mjit_gc_wakeup);
        verbose(1, "Failure in MJIT thread initialization\n");
    }
}

/* Finish the threads processing units and creating PCH, finalize
   and free MJIT data.  It should be called last during MJIT
   life.  */
void
mjit_finish(void)
{
    if (!mjit_init_p)
        return;

    /* Wait for pch finish */
    verbose(2, "Canceling pch and worker threads");
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
    stop_worker_p = TRUE;
    while (!worker_stopped) {
        verbose(3, "Sending cancel signal to workers");
        CRITICAL_SECTION_START(3, "in mjit_finish");
        rb_native_cond_broadcast(&mjit_worker_wakeup);
        CRITICAL_SECTION_FINISH(3, "in mjit_finish");
    }

    rb_native_mutex_destroy(&mjit_engine_mutex);
    rb_native_cond_destroy(&mjit_pch_wakeup);
    rb_native_cond_destroy(&mjit_client_wakeup);
    rb_native_cond_destroy(&mjit_worker_wakeup);
    rb_native_cond_destroy(&mjit_gc_wakeup);

    /* cleanup temps */
    if (!mjit_opts.save_temps)
        remove_file(pch_file);

    xfree(tmp_dir); tmp_dir = NULL;
    xfree(pch_file); pch_file = NULL;
    xfree(header_file); header_file = NULL;

    free_list(&unit_queue);
    free_list(&active_units);
    finish_conts();

    mjit_init_p = FALSE;
    verbose(1, "Successful MJIT finish");
}

void
mjit_mark(void)
{
    struct rb_mjit_unit_node *node;
    if (!mjit_init_p)
        return;
    RUBY_MARK_ENTER("mjit");
    CRITICAL_SECTION_START(4, "mjit_mark");
    for (node = unit_queue.head; node != NULL; node = node->next) {
        if (node->unit->iseq) { /* ISeq is still not GCed */
            VALUE iseq = (VALUE)node->unit->iseq;
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

/* A hook to update valid_class_serials. This should NOT be used in MJIT worker. */
void
mjit_add_class_serial(rb_serial_t class_serial)
{
    if (!mjit_init_p)
        return;

    /* Do not wrap CRITICAL_SECTION here. This function is only called in main thread
       and guarded by GVL, and `rb_hash_aset` may cause GC and deadlock in it. */
    rb_hash_aset(valid_class_serials, LONG2FIX(class_serial), Qtrue);
}

/* A hook to update valid_class_serials. This should NOT be used in MJIT worker. */
void
mjit_remove_class_serial(rb_serial_t class_serial)
{
    if (!mjit_init_p)
        return;

    CRITICAL_SECTION_START(3, "in mjit_remove_class_serial");
    rb_hash_delete_entry(valid_class_serials, LONG2FIX(class_serial));
    CRITICAL_SECTION_FINISH(3, "in mjit_remove_class_serial");
}

/* Return TRUE if class_serial is not obsoleted. This can be used in MJIT worker. */
int
mjit_valid_class_serial_p(rb_serial_t class_serial)
{
    int found_p;

    CRITICAL_SECTION_START(3, "in valid_class_serial_p");
    found_p = st_lookup(RHASH_TBL_RAW(valid_class_serials), LONG2FIX(class_serial), NULL);
    CRITICAL_SECTION_FINISH(3, "in valid_class_serial_p");
    return found_p;
}
