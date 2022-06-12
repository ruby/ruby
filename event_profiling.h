#ifndef RUBY_EVENT_PROFILING_H
#define RUBY_EVENT_PROFILING_H 1

#ifndef USE_EVENT_PROFILING
#define USE_EVENT_PROFILING 0
#endif

#if USE_EVENT_PROFILING

#include "ruby/internal/config.h"

#include "vm_core.h"

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#if !defined(__GNUC__) && USE_EVENT_PROFILING
#error "USE_EVENT_PROFILING is not supported by other than __GNUC__"
#endif

/* To avoid using realloc, allocate large heap memory ahead of execution. */
typedef struct rb_event_profiling_config
{
    int max_ractors;
    int max_ractor_events;
    int max_call_stack_depth;
} rb_event_profiling_config_t;

typedef struct rb_event_profiling
{
    /* Title: file:function(id) Args: line, ractor */
    const char *file;
    const char *function;
    int line;
    int ractor;
    int id;

    pid_t pid;
    pid_t tid;

    enum
    {
        EVENT_PROFILING_PHASE_BEGIN,
        EVENT_PROFILING_PHASE_END,
        EVENT_PROFILING_PHASE_SNAPSHOT,
    } phase;

    const char *snapshot_reason;
    const char *customized_name;

    time_t timestamp;
} rb_event_profiling_event_t;

/* Allocate an event list for each Ractor */
typedef struct rb_event_profiling_list
{
    int last_event_id;
    int tail;

    struct
    {
        int top;
        int *event_indexes;
    } call_stack;

    rb_event_profiling_event_t *events;
} rb_event_profiling_list_t;

typedef struct rb_event_profiling_bucket
{
    rb_event_profiling_list_t *system_init_event_list;
    rb_event_profiling_list_t **ractor_profiling_event_lists;
    int ractors;
} rb_event_profiling_bucket_t;

MJIT_FUNC_EXPORTED rb_event_profiling_config_t *rb_setup_event_profiling(int
                                                                         max_ractors,
                                                                         int
                                                                         max_ractor_events,
                                                                         int
                                                                         max_call_stack_depth);

MJIT_FUNC_EXPORTED void rb_finalize_event_profiling(const char *outfile);

MJIT_FUNC_EXPORTED int
rb_event_profiling_begin(const char *file,
                         const char *func, int line,
                         const char *customized_name, bool system);

MJIT_FUNC_EXPORTED int rb_event_profiling_end(const char *file,
                                              const char *func, int line,
                                              const char *customized_name,
                                              bool system);

MJIT_FUNC_EXPORTED void rb_event_profiling_exception(bool system);

MJIT_FUNC_EXPORTED int
rb_event_profiling_snapshot(const char *file,
                            const char *func, int line,
                            const char *reason, bool system);

MJIT_FUNC_EXPORTED void rb_event_profiling_ractor_init(rb_ractor_t * r);

#define RB_EVENT_PROFILING_DEFAULT_FILE_NAME     __FILE__
#define RB_EVENT_PROFILING_DEFAULT_FUNCTION_NAME __func__
#define RB_EVENT_PROFILING_DEFAULT_LINE_NUMBER   __LINE__
#define RB_EVENT_PROFILING_UNNAMED                                             \
    __FILE__, __func__, __LINE__, NULL  /* disable customized event name */
#define RB_EVENT_PROFILING_NAMED __FILE__, __func__, __LINE__

/* Public marcos */

/* Use in ractor.c */
#define RB_EVENT_PROFILING_RACTOR_INIT(ractor)                                 \
    rb_event_profiling_ractor_init(ractor)

/* Per-ractor profiling */
#define RB_EVENT_PROFILING_BEGIN_DEFAULT()                                     \
    rb_event_profiling_begin(RB_EVENT_PROFILING_UNNAMED, false)
#define RB_EVENT_PROFILING_END_DEFAULT()                                       \
    rb_event_profiling_end(RB_EVENT_PROFILING_UNNAMED, false)
#define RB_EVENT_PROFILING_BEGIN(name)                                         \
    rb_event_profiling_begin(RB_EVENT_PROFILING_NAMED, name, false)
#define RB_EVENT_PROFILING_END(name)                                           \
    rb_event_profiling_end(RB_EVENT_PROFILING_NAMED, name, false)
#define RB_EVENT_PROFILING_SNAPSHOT(reason)                                    \
    rb_event_profiling_snapshot(RB_EVENT_PROFILING_NAMED, reason, false)
#define RB_EVENT_PROFILING_EXCEPTION() rb_event_profiling_exception(false)

/* Profile before main rector creation */
#define RB_SYSTEM_EVENT_PROFILING_BEGIN_DEFAULT()                              \
    rb_event_profiling_begin(RB_EVENT_PROFILING_UNNAMED, true)
#define RB_SYSTEM_EVENT_PROFILING_END_DEFAULT()                                \
    rb_event_profiling_end(RB_EVENT_PROFILING_UNNAMED, true)
#define RB_SYSTEM_EVENT_PROFILING_BEGIN(name)                                  \
    rb_event_profiling_begin(RB_EVENT_PROFILING_NAMED, name, true)
#define RB_SYSTEM_EVENT_PROFILING_END(name)                                    \
    rb_event_profiling_end(RB_EVENT_PROFILING_NAMED, name, true)
#define RB_SYSTEM_EVENT_PROFILING_SNAPSHOT(reason)                             \
    rb_event_profiling_snapshot(RB_EVENT_PROFILING_NAMED, reason, true)
#define RB_SYSTEM_EVENT_PROFILING_EXCEPTION() rb_event_profiling_exception(true)

/* Record the first event in ruby_sysinit()
   and the last event in rb_ec_cleanup() */
#define RB_EVENT_PROFILING_SYSTEM_INIT_CLEANUP_INFO "ruby", "total", 0, NULL
#define RB_SYSTEM_INIT_EVENT_PROFILING()                                       \
    rb_event_profiling_begin(RB_EVENT_PROFILING_SYSTEM_INIT_CLEANUP_INFO, true)
#define RB_SYSTEM_CLEANUP_EVENT_PROFILING()                                    \
    rb_event_profiling_end(RB_EVENT_PROFILING_SYSTEM_INIT_CLEANUP_INFO, true)

/* Setup and clean up the event-based profiling */
#define RB_EVENT_PROFILING_DEFAULT_MAX_RACTORS          (512)
#define RB_EVENT_PROFILING_DEFAULT_MAX_RACTOR_EVENTS    (8192 * 512)
#define RB_EVENT_PROFILING_DEFAULT_MAX_CALL_STACK_DEPTH (64)
#define RB_EVENT_PROFILING_DEFAULT_OUTFILE              "event_profiling_out.json"

#define RB_SETUP_EVENT_PROFILING(max_ractors, max_ractor_events,               \
                                 max_call_stack_depth)                         \
    rb_setup_event_profiling(max_ractors, max_ractor_events,                   \
                             max_call_stack_depth)
#define RB_SETUP_EVENT_PROFILING_DEFAULT()                                     \
    rb_setup_event_profiling(RB_EVENT_PROFILING_DEFAULT_MAX_RACTORS,           \
                             RB_EVENT_PROFILING_DEFAULT_MAX_RACTOR_EVENTS,     \
                             RB_EVENT_PROFILING_DEFAULT_MAX_CALL_STACK_DEPTH)
#define RB_FINALIZE_EVENT_PROFILING(outfile)                                   \
    rb_finalize_event_profiling(outfile)
#define RB_FINALIZE_EVENT_PROFILING_DEFAULT()                                  \
    rb_finalize_event_profiling(RB_EVENT_PROFILING_DEFAULT_OUTFILE)

#else

#define RB_EVENT_PROFILING_RACTOR_INIT(ractor)
#define RB_EVENT_PROFILING_BEGIN_DEFAULT()
#define RB_EVENT_PROFILING_END_DEFAULT()
#define RB_EVENT_PROFILING_BEGIN(name)
#define RB_EVENT_PROFILING_END(name)
#define RB_EVENT_PROFILING_SNAPSHOT(reason)
#define RB_EVENT_PROFILING_EXCEPTION()
#define RB_SYSTEM_EVENT_PROFILING_BEGIN_DEFAULT()
#define RB_SYSTEM_EVENT_PROFILING_END_DEFAULT()
#define RB_SYSTEM_EVENT_PROFILING_BEGIN(name)
#define RB_SYSTEM_EVENT_PROFILING_END(name)
#define RB_SYSTEM_EVENT_PROFILING_SNAPSHOT(reason)
#define RB_SYSTEM_EVENT_PROFILING_EXCEPTION()
#define RB_SYSTEM_INIT_EVENT_PROFILING()
#define RB_SYSTEM_CLEANUP_EVENT_PROFILING()
#define RB_SETUP_EVENT_PROFILING_DEFAULT()
#define RB_FINALIZE_EVENT_PROFILING_DEFAULT()

#endif /* USE_EVENT_PROFILING */

#endif /* RUBY_EVENT_PROFILING_H */
