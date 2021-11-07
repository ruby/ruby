#include "event_profiling.h"

#if USE_EVENT_PROFILING

/* Ruby */
#include "ractor_core.h"
#include "ruby.h"
#include "ruby/atomic.h"
#include "ruby/thread_native.h"
#include "vm_core.h"

/* GCC warning */
#include <sys/syscall.h>
pid_t
gettid(void)
{
    return syscall(SYS_gettid);
}

/* Global config */
static rb_event_profiling_config_t *rb_event_profiling_config;

/* Global bucket */
static rb_event_profiling_bucket_t *rb_event_profiling_bucket;

/* Phase strings */
static const char rb_event_profiling_phase_str[] = { 'B', 'E', 'O' };

/* Internal functions */
static inline int
get_total_events(void)
{
    int total = rb_event_profiling_bucket->system_init_event_list->tail;
    int ractors = rb_event_profiling_bucket->ractors;
    for (int i = 0; i < ractors; i++) {
        rb_event_profiling_list_t *list =
            rb_event_profiling_bucket->ractor_profiling_event_lists[i];
        total += list->tail;
    }

    return total;
}

static inline time_t
microsecond_timestamp(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    time_t us = t.tv_sec * 1E6 + t.tv_nsec / 1E3;

    return us;
}

static inline rb_event_profiling_list_t *
init_profiling_event_list(void)
{
    rb_event_profiling_list_t *list =
        malloc(sizeof(rb_event_profiling_list_t));

    rb_event_profiling_event_t *events =
        malloc(sizeof(rb_event_profiling_event_t) *
               rb_event_profiling_config->max_ractor_events);

    int *event_indexes =
        malloc(sizeof(int) * rb_event_profiling_config->max_call_stack_depth);

    list->tail = 0;
    list->last_event_id = 0;
    list->events = events;

    list->call_stack.top = 0;
    list->call_stack.event_indexes = event_indexes;

    return list;
}

static inline rb_event_profiling_list_t *
select_event_list(bool system)
{
    if (system) {
        return rb_event_profiling_bucket->system_init_event_list;
    }
    else {
        return GET_RACTOR()->event_profiling_storage;
    }
}

static inline rb_event_profiling_event_t *
get_an_event_slot(bool system, int *ret_index)
{
    rb_event_profiling_list_t *list = select_event_list(system);
    int index = list->tail++;

    rb_event_profiling_event_t *event = &(list->events[index]);

    event->ractor = system ? 0 : GET_RACTOR()->pub.id;

    if (ret_index != NULL) {
        *ret_index = index;
    }
    return event;
}

static inline int
get_a_new_event_id(bool system)
{
    rb_event_profiling_list_t *list = select_event_list(system);
    return list->last_event_id++;
}

static inline int
serialize_event(const rb_event_profiling_event_t * event,
                char *buffer, int offset)
{
    char *event_buffer = buffer + offset;
    int count = 0;

    switch (event->phase) {
    case EVENT_PROFILING_PHASE_SNAPSHOT:
        count = sprintf(event_buffer,
                        "{\"name\": \"snapshot-%d\",\n"
                        "\"id\":\"%d(%d)\",\n"
                        "\"ph\":\"%c\",\n"
                        "\"pid\":\"%i\",\n"
                        "\"tid\":\"%i\",\n"
                        "\"ts\":\"%ld\",\n"
                        "\"args\": {\"snapshot\":{\"name\": \"%s:%s(%d)\", "
                        "\"line\": \"%d\", "
                        "\"ractor\":\"%d\",\"reason\": \"%s\"}}},\n",
                        event->tid, event->tid, event->id,
                        rb_event_profiling_phase_str[event->phase],
                        event->pid, event->tid, event->timestamp, event->file,
                        event->function, event->id, event->line,
                        event->ractor, event->snapshot_reason);
        break;
    case EVENT_PROFILING_PHASE_BEGIN:
    case EVENT_PROFILING_PHASE_END:
        if (event->customized_name == NULL) {
            count = sprintf(event_buffer, "{\"name\": \"%s:%s(%d)\",\n",
                            event->file, event->function, event->id);
        }
        else {
            count = sprintf(event_buffer, "{\"name\": \"%s(%d)\",\n",
                            event->customized_name, event->id);
        }
        count +=
            sprintf(event_buffer + count,
                    "\"ph\":\"%c\",\n"
                    "\"pid\":\"%i\",\n"
                    "\"tid\":\"%i\",\n"
                    "\"ts\":%ld,\n"
                    "\"args\": {\"line\": \"%d\", \"ractor\":\"%d\"}},\n",
                    rb_event_profiling_phase_str[event->phase], event->pid,
                    event->tid, event->timestamp, event->line, event->ractor);
        break;
    default:
        fprintf(stderr, "[ERROR] event_profiling: unknown phase %d\n",
                event->phase);
        count = -1;
        break;
    }

    return count;
}

static inline int
serialize_event_list(const rb_event_profiling_list_t * list,
                     char *buffer, int offset)
{
    int events = list->tail;
    int list_offset = offset;
    for (int i = 0; i < events; i++) {
        list_offset +=
            serialize_event(&(list->events[i]), buffer, list_offset);
    }
    return list_offset;
}

static inline void
destroy_event_list(rb_event_profiling_list_t * list)
{
    free(list->events);
    free(list->call_stack.event_indexes);
    free(list);
}

static inline void
destroy_profiling_event_bucket(void)
{
    int ractors = rb_event_profiling_bucket->ractors;
    for (int i = 0; i < ractors; i++) {
        destroy_event_list(rb_event_profiling_bucket->
                           ractor_profiling_event_lists[i]);
    }

    free(rb_event_profiling_bucket->system_init_event_list);
    free(rb_event_profiling_bucket->ractor_profiling_event_lists);
    free(rb_event_profiling_bucket);
}

static inline rb_event_profiling_bucket_t *
init_event_bucket(void)
{
    rb_event_profiling_bucket_t *bucket =
        malloc(sizeof(rb_event_profiling_bucket_t));
    bucket->system_init_event_list = init_profiling_event_list();
    bucket->ractor_profiling_event_lists =
        malloc(sizeof(rb_event_profiling_list_t *) *
               rb_event_profiling_config->max_ractors);
    bucket->ractors = 0;

    rb_event_profiling_bucket = bucket;
    return bucket;
}

static inline void
serialize_event_bucket(const char *outfile)
{
    /* Prepare the buffer */
    int json_symbol_size = 64;
    int event_buffer_size = 256;
    int total_events = get_total_events();
    int buffer_size = total_events * (event_buffer_size + json_symbol_size) +
        json_symbol_size;
    char *bucket_buffer = malloc(sizeof(char) * buffer_size);

    /* Serialize */
    int offset = sprintf(bucket_buffer, "[");
    int ractors = rb_event_profiling_bucket->ractors;

    offset =
        serialize_event_list(rb_event_profiling_bucket->
                             system_init_event_list, bucket_buffer, offset);
    for (int i = 0; i < ractors; i++) {
        rb_event_profiling_list_t *list =
            rb_event_profiling_bucket->ractor_profiling_event_lists[i];
        offset = serialize_event_list(list, bucket_buffer, offset);
    }
    int final_offset = (offset > 1) ? offset - 2 : 1;
    sprintf(bucket_buffer + final_offset, "]\n");       /* Remove the last `,` */

    /* Output to a file */
    FILE *stream = fopen(outfile, "w");
    /* TestProcess#test_no_curdir: cannot open log file in current directory */
    if(stream == NULL)
    {
        fprintf(stderr, "event_profiling: cannot open %s\n", outfile);
        free(bucket_buffer);
        return;
    }
    fputs(bucket_buffer, stream);
    fclose(stream);

    free(bucket_buffer);
}

static inline int
push_call_stack(int index, bool system)
{
    rb_event_profiling_list_t *list = select_event_list(system);

    int i = list->call_stack.top++;

    list->call_stack.event_indexes[i] = index;
    return index;
}

static inline rb_event_profiling_event_t *
pop_call_stack(bool system)
{
    rb_event_profiling_list_t *list = select_event_list(system);

    int i = --(list->call_stack.top);
    int index = list->call_stack.event_indexes[i];

    rb_event_profiling_event_t *event = &(list->events[index]);
    return event;
}

static bool
call_stack_empty(bool system)
{
    rb_event_profiling_list_t *list = select_event_list(system);
    return list->call_stack.top == 0;
}

/* Public functions */

void
rb_event_profiling_ractor_init(rb_ractor_t * r)
{
    int ractor_id = r->pub.id;
    RUBY_ATOMIC_INC(rb_event_profiling_bucket->ractors);

    rb_event_profiling_list_t *list = init_profiling_event_list();
    r->event_profiling_storage = list;

    /* Save a pointer to serialize all events before MRI main ractor exiting */
    rb_event_profiling_bucket->ractor_profiling_event_lists[ractor_id - 1] =
        list;
}

int
rb_event_profiling_begin(const char *file, const char *func, int line,
                         const char *customized_name, bool system)
{
    int index = -1;
    rb_event_profiling_event_t *event = get_an_event_slot(system, &index);

    /* Track this event */
    push_call_stack(index, system);

    int id = get_a_new_event_id(system);

    event->file = file;
    event->function = func;
    event->line = line;
    event->id = id;
    event->phase = EVENT_PROFILING_PHASE_BEGIN;
    event->pid = getpid();
    event->tid = gettid();
    event->snapshot_reason = NULL;
    event->customized_name = customized_name;
    event->timestamp = microsecond_timestamp();

    return id;
}

int
rb_event_profiling_end(const char *file, const char *func, int line,
                       const char *customized_name, bool system)
{
    rb_event_profiling_event_t *event = get_an_event_slot(system, NULL);

    rb_event_profiling_event_t *begin = pop_call_stack(system);
    int id = begin->id;

    event->file = file;
    event->function = func;
    event->line = line;
    event->id = id;
    event->phase = EVENT_PROFILING_PHASE_END;
    event->pid = begin->pid;
    event->tid = begin->tid;
    event->snapshot_reason = NULL;
    event->customized_name = customized_name;
    event->timestamp = microsecond_timestamp();

    return id;
}

void
rb_event_profiling_exception(bool system)
{
    while (!call_stack_empty(system)) {
        rb_event_profiling_event_t *event = get_an_event_slot(system, NULL);

        rb_event_profiling_event_t *begin = pop_call_stack(system);

        event->file = begin->file;
        event->function = begin->function;
        event->line = -1;
        event->id = begin->id;
        event->phase = EVENT_PROFILING_PHASE_END;
        event->pid = begin->pid;
        event->tid = begin->tid;
        event->snapshot_reason = NULL;
        event->timestamp = microsecond_timestamp();
    }
}

int
rb_event_profiling_snapshot(const char *file, const char *func, int line,
                            const char *reason, bool system)
{
    rb_event_profiling_event_t *event = get_an_event_slot(system, NULL);
    int id = get_a_new_event_id(system);

    event->file = file;
    event->function = func;
    event->line = line;
    event->id = id;
    event->phase = EVENT_PROFILING_PHASE_SNAPSHOT;
    event->pid = getpid();
    event->tid = gettid();
    event->snapshot_reason = reason;
    event->timestamp = microsecond_timestamp();

    return id;
}

rb_event_profiling_config_t *
rb_setup_event_profiling(int max_ractors,
                         int max_ractor_events, int max_call_stack_depth)
{
    rb_event_profiling_config_t *config =
        malloc(sizeof(rb_event_profiling_config_t));
    config->max_ractors = max_ractors;
    config->max_ractor_events = max_ractor_events;
    config->max_call_stack_depth = max_call_stack_depth;

    rb_event_profiling_config = config;

    init_event_bucket();

    return config;
}

void
rb_finalize_event_profiling(const char *outfile)
{
    serialize_event_bucket(outfile);

    destroy_profiling_event_bucket();
    free(rb_event_profiling_config);

    rb_event_profiling_config = NULL;
    rb_event_profiling_bucket = NULL;
}

#else

/* ISO C requires a translation unit to contain at least one declaration */
void
rb_event_profiling_disabled(void)
{
}

#endif /* USE_EVENT_PROFILING */
