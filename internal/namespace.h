#ifndef INTERNAL_NAMESPACE_H                                  /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_NAMESPACE_H

#include "ruby/ruby.h"          /* for VALUE */

/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Namespace.
 */
struct rb_namespace_struct {
    /*
     * To retrieve Namespace object that provides #require and so on.
     * That is used from load.c, etc., that uses rb_namespace_t internally.
     */
    VALUE ns_object;
    long ns_id; // namespace id to generate ext filenames

    VALUE top_self;

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

    bool is_user;
    bool is_optional;
};
typedef struct rb_namespace_struct rb_namespace_t;

#define NAMESPACE_OBJ_P(obj) (rb_obj_class(obj) == rb_cNamespace)

#define NAMESPACE_ROOT_P(ns) (ns && !ns->is_user)
#define NAMESPACE_USER_P(ns) (ns && ns->is_user)
#define NAMESPACE_OPTIONAL_P(ns) (ns && ns->is_optional)
#define NAMESPACE_MAIN_P(ns) (ns && ns->is_user && !ns->is_optional)

#define NAMESPACE_METHOD_DEFINITION(mdef) (mdef ? mdef->ns : NULL)
#define NAMESPACE_METHOD_ENTRY(me) (me ? NAMESPACE_METHOD_DEFINITION(me->def) : NULL)
#define NAMESPACE_CC(cc) (cc ? NAMESPACE_METHOD_ENTRY(cc->cme_) : NULL)
#define NAMESPACE_CC_ENTRIES(ccs) (ccs ? NAMESPACE_METHOD_ENTRY(ccs->cme) : NULL)

RUBY_EXTERN bool ruby_namespace_enabled;
RUBY_EXTERN bool ruby_namespace_init_done;
RUBY_EXTERN bool ruby_namespace_crashed;

static inline bool
rb_namespace_available(void)
{
    return ruby_namespace_enabled;
}

const rb_namespace_t * rb_root_namespace(void);
const rb_namespace_t * rb_main_namespace(void);
const rb_namespace_t * rb_current_namespace(void);
const rb_namespace_t * rb_loading_namespace(void);
const rb_namespace_t * rb_current_namespace_in_crash_report(void);

void rb_namespace_entry_mark(void *);
void rb_namespace_gc_update_references(void *ptr);

rb_namespace_t * rb_get_namespace_t(VALUE ns);
VALUE rb_get_namespace_object(rb_namespace_t *ns);

VALUE rb_namespace_local_extension(VALUE namespace, VALUE fname, VALUE path);

void rb_initialize_main_namespace(void);
void rb_namespace_init_done(void);
#endif /* INTERNAL_NAMESPACE_H */
