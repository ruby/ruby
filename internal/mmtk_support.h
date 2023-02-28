#ifndef INTERNAL_MMTK_SUPPORT_H                                 /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_MMTK_SUPPORT_H

#include "ruby/internal/config.h"

#if !USE_MMTK
#error This file should only be included when MMTk is enabled. Guard the #include with #if USE_MMTK
#endif

#include "ruby/ruby.h"

#define MMTK_DEFAULT_PLAN "MarkSweep"

// Enabled?
bool rb_mmtk_enabled_p(void);

// Initialization
void rb_gc_init_collection(void);
void rb_mmtk_main_thread_init(void);

// Object layout
size_t rb_mmtk_prefix_size(void);
size_t rb_mmtk_suffix_size(void);

// Tracing
void rb_mmtk_mark_movable(VALUE obj);
void rb_mmtk_mark_pin(VALUE obj);
void rb_mmtk_mark_and_move(VALUE *field);
bool rb_mmtk_object_moved_p(VALUE obj);
VALUE rb_mmtk_maybe_forward(VALUE object);

// Finalization and exiting
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

// MMTk-specific Ruby module (GC::MMTk)
void rb_mmtk_define_gc_mmtk_module(void);
VALUE rb_mmtk_plan_name(VALUE _);
VALUE rb_mmtk_enabled(VALUE _);
VALUE rb_mmtk_harness_begin(VALUE _);
VALUE rb_mmtk_harness_end(VALUE _);

// Debugging
void rb_mmtk_assert_mmtk_worker(void);
void rb_mmtk_assert_mutator(void);

// Commandline options parsing
void rb_mmtk_pre_process_opts(int argc, char **argv);
void rb_mmtk_post_process_opts(const char *arg);
void rb_mmtk_post_process_opts_finish(bool feature_enable);

#endif // INTERNAL_MMTK_SUPPORT_H
