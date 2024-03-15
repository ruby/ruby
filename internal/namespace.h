#ifndef INTERNAL_NAMESPACE_H                                  /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_NAMESPACE_H

#include "ruby/ruby.h"          /* for VALUE */

/**
 * @author     Satoshi Tagomori <tagomoris@gmail.com>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Fiber.
 */
struct rb_namespace_struct {
    /*
     * To retrieve Namespace object that provides #require and so on.
     * That is used from load.c, etc., that uses rb_namespace_t internally.
     */
    VALUE ns_object;
    long ns_id; // namespace id to generate ext filenames
    char is_local;

    VALUE top_self;
    VALUE refiner;

    VALUE load_path;
    VALUE load_path_snapshot;
    VALUE load_path_check_cache;
    VALUE expanded_load_path;
    VALUE loaded_features;
    VALUE loaded_features_snapshot;
    VALUE loaded_features_realpaths;
    VALUE loaded_features_realpath_map;
    struct st_table *loaded_features_index;
    struct st_table *loading_table;
    VALUE ruby_dln_libmap;

    VALUE gvar_tbl;
};
typedef struct rb_namespace_struct rb_namespace_t;

#define NAMESPACE_LOCAL_P(ns) (ns && ns->is_local)

int rb_namespace_available(void);
rb_namespace_t * rb_global_namespace(void);
const rb_namespace_t * rb_current_namespace(void);

VALUE rb_namespace_of(VALUE klass);
VALUE rb_klass_defined_under_namespace_p(VALUE klass, VALUE namespace);
VALUE rb_mod_changed_in_current_namespace(VALUE mod);

void rb_namespace_entry_mark(void *);

rb_namespace_t * rb_namespace_alloc_init(void);
rb_namespace_t * rb_get_namespace_t(VALUE ns);

VALUE rb_namespace_local_extension(VALUE namespace, VALUE path);

void rb_initialize_global_namespace(void);

#endif /* INTERNAL_NAMESPACE_H */
