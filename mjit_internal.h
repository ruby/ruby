/**********************************************************************

  mjit_internal.h - Utility functions shared by mjit*.c

  Copyright (C) 2018 Takashi Kokubun <takashikkbn@gmail.com>.

**********************************************************************/

/* NOTE: All functions in this file can be executed on MJIT worker. So don't
   call Ruby methods (C functions that may call rb_funcall) or trigger
   GC (using xmalloc, ZALLOC, etc.) in this file. */

#ifndef RUBY_MJIT_INTERNAL_H
#define RUBY_MJIT_INTERNAL_H 1

#include "mjit.h"

#ifndef MAXPATHLEN
#  define MAXPATHLEN 1024
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

#endif /* RUBY_MJIT_INTERNAL_H */
