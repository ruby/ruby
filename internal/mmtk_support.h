#ifndef INTERNAL_MMTK_SUPPORT_H                                 /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_MMTK_SUPPORT_H

#include "ruby/internal/config.h"

#if !USE_MMTK
#error This file should only be included when MMTk is enabled. Guard the #include with #if USE_MMTK
#endif

#include "ruby/ruby.h"
#include "internal/mmtk.h"

#define MMTK_DEFAULT_PLAN "MarkSweep"

#define MMTK_ALLOCATION_SEMANTICS_DEFAULT 0
#define MMTK_ALLOCATION_SEMANTICS_LOS 1
#define MMTK_MAX_IMMIX_OBJECT_SIZE 16384

// Special imemo data structures.

// String's underlying buffer.
typedef struct {
    VALUE flags; /* imemo header */
    size_t capa;
    char ary[]; // The actual content.
} rb_mmtk_strbuf_t;

// Enabled?
bool rb_mmtk_enabled_p(void);

// Initialization
void rb_mmtk_bind_mutator(MMTk_VMMutatorThread cur_thread);
void rb_mmtk_main_thread_init(void);

// Flushing and de-initialization
void rb_mmtk_flush_mutator_local_buffers(MMTk_VMMutatorThread thread);
void rb_mmtk_destroy_mutator(MMTk_VMMutatorThread cur_thread);

// Object layout
size_t rb_mmtk_prefix_size(void);
size_t rb_mmtk_suffix_size(void);

// Allocation
VALUE rb_mmtk_alloc_obj(size_t mmtk_alloc_size, size_t size_pool_size, size_t prefix_size);

// Tracing
void rb_mmtk_mark_movable(VALUE obj);
void rb_mmtk_mark_pin(VALUE obj);
void rb_mmtk_mark_and_move(VALUE *field);
bool rb_mmtk_object_moved_p(VALUE obj);
VALUE rb_mmtk_maybe_forward(VALUE object);

// PPP support
void rb_mmtk_maybe_register_ppp(VALUE obj);

// Finalization and exiting
void rb_mmtk_maybe_register_obj_free_candidate(VALUE obj);
int rb_mmtk_run_finalizers_immediately(st_data_t key, st_data_t value, st_data_t data);
void rb_mmtk_call_obj_free_on_exit(void);

bool rb_gc_obj_free_on_exit_started(void);
void rb_gc_set_obj_free_on_exit_started(void);

// Weak table processing
typedef void (*rb_mmtk_hash_on_delete_func)(st_data_t, st_data_t, void *arg);

void
rb_mmtk_update_weak_table(st_table *table,
                          bool addr_hashed,
                          bool update_values,
                          rb_mmtk_hash_on_delete_func on_delete,
                          void *on_delete_arg);

void rb_mmtk_update_global_weak_tables_early(void);
void rb_mmtk_update_global_weak_tables(void);

// String buffer implementation
rb_mmtk_strbuf_t *rb_mmtk_new_strbuf(size_t capa);
char* rb_mmtk_strbuf_to_chars(rb_mmtk_strbuf_t* strbuf);

// MMTk-specific Ruby module (GC::MMTk)
void rb_mmtk_define_gc_mmtk_module(void);
VALUE rb_mmtk_plan_name(VALUE _);
VALUE rb_mmtk_enabled(VALUE _);
VALUE rb_mmtk_harness_begin(VALUE _);
VALUE rb_mmtk_harness_end(VALUE _);

// Debugging
void rb_mmtk_assert_mmtk_worker(void);
void rb_mmtk_assert_mutator(void);

// Vanilla GC timing
void rb_mmtk_gc_probe(bool enter);
void rb_mmtk_gc_probe_slowpath(bool enter);

// xmalloc accounting
void rb_mmtk_xmalloc_increase_body(size_t new_size, size_t old_size);

// Commandline options parsing
void rb_mmtk_pre_process_opts(int argc, char **argv);
void rb_mmtk_post_process_opts(const char *arg);
void rb_mmtk_post_process_opts_finish(bool feature_enable);

#endif // INTERNAL_MMTK_SUPPORT_H
