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

#define IS_NAMESPACE(obj) (CLASS_OF(obj) == rb_cNamespace)
#define IS_IN_NAMESPACE(th) (th->ns && th->ns->is_local)
#define NAMESPACE_LOCAL_P(ns) (ns && ns->is_local)

#define CURRENT_NS_x(th, attr) (IS_IN_NAMESPACE(th) ? th->ns->attr : th->vm->attr)
#define SET_NS_x(th, attr, value) do {    \
    if (IS_IN_NAMESPACE(th)) { th->ns->attr = value; } \
    else { th->vm->attr = value; }            \
} while (0)

#define CURRENT_LOAD_PATH(th)             CURRENT_NS_x(th, load_path)
#define CURRENT_LOAD_PATH_SNAPSHOT(th)    CURRENT_NS_x(th, load_path_snapshot)
#define CURRENT_LOAD_PATH_CHECK_CACHE(th) CURRENT_NS_x(th, load_path_check_cache)
#define CURRENT_EXPANDED_LOAD_PATH(th)    CURRENT_NS_x(th, expanded_load_path)
#define CURRENT_LOADED_FEATURES(th)              CURRENT_NS_x(th, loaded_features)
#define CURRENT_LOADED_FEATURES_SNAPSHOT(th)     CURRENT_NS_x(th, loaded_features_snapshot)
#define CURRENT_LOADED_FEATURES_REALPATHS(th)    CURRENT_NS_x(th, loaded_features_realpaths)
#define CURRENT_LOADED_FEATURES_REALPATH_MAP(th) CURRENT_NS_x(th, loaded_features_realpath_map)
#define CURRENT_LOADED_FEATURES_INDEX(th)        CURRENT_NS_x(th, loaded_features_index)
#define CURRENT_LOADING_TABLE(th) CURRENT_NS_x(th, loading_table)

#define CURRENT_RUBY_DLN_LIBMAP(th, map) (IS_IN_NAMESPACE(th) ? th->ns->ruby_dln_libmap : map)

#define SET_LOAD_PATH_CHECK_CACHE(th, value) SET_NS_x(th, load_path_check_cache, value)
#define SET_EXPANDED_LOAD_PATH(th, value) SET_NS_x(th, expanded_load_path, value)

int rb_namespace_available(void);
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
