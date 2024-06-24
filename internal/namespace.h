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

    bool is_builtin;
    bool is_local;
};
typedef struct rb_namespace_struct rb_namespace_t;

#define NAMESPACE_BUILTIN_P(ns) (ns && ns->is_builtin)
#define NAMESPACE_LOCAL_P(ns) (ns && ns->is_local)
#define NAMESPACE_EFFECTIVE_P(ns) (ns && !ns->is_builtin)

#define NAMESPACE_METHOD_DEFINITION(mdef) (mdef ? mdef->ns : NULL)
#define NAMESPACE_METHOD_ENTRY(me) (me ? NAMESPACE_METHOD_DEFINITION(me->def) : NULL)
#define NAMESPACE_CC(cc) (cc ? NAMESPACE_METHOD_ENTRY(cc->cme_) : NULL)
#define NAMESPACE_CC_ENTRIES(ccs) (ccs ? NAMESPACE_METHOD_ENTRY(ccs->cme) : NULL)

int rb_namespace_available(void);
void rb_namespace_enable_builtin(void);
void rb_namespace_disable_builtin(void);
rb_namespace_t * rb_main_namespace(void);
const rb_namespace_t * rb_current_namespace(void);

void rb_namespace_entry_mark(void *);

rb_namespace_t * rb_get_namespace_t(VALUE ns);

VALUE rb_namespace_local_extension(VALUE namespace, VALUE path);

void rb_initialize_main_namespace(void);

#endif /* INTERNAL_NAMESPACE_H */
