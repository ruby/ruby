#ifndef INTERNAL_BOX_H                                  /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_BOX_H

#include "ruby/ruby.h"          /* for VALUE */

/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Ruby Box.
 */
struct rb_box_struct {
    /*
     * To retrieve Ruby::Box object that provides #require and so on.
     * That is used from load.c, etc., that uses rb_box_t internally.
     */
    VALUE box_object;
    long box_id; // box_id to generate ext filenames

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
    struct st_table *classext_cow_classes;

    bool is_user;
    bool is_optional;
};
typedef struct rb_box_struct rb_box_t;

#define BOX_OBJ_P(obj) (rb_obj_class(obj) == rb_cBox)

#define BOX_ROOT_P(box) (box && !box->is_user)
#define BOX_USER_P(box) (box && box->is_user)
#define BOX_OPTIONAL_P(box) (box && box->is_optional)
#define BOX_MAIN_P(box) (box && box->is_user && !box->is_optional)

#define BOX_METHOD_DEFINITION(mdef) (mdef ? mdef->ns : NULL)
#define BOX_METHOD_ENTRY(me) (me ? BOX_METHOD_DEFINITION(me->def) : NULL)
#define BOX_CC(cc) (cc ? BOX_METHOD_ENTRY(cc->cme_) : NULL)
#define BOX_CC_ENTRIES(ccs) (ccs ? BOX_METHOD_ENTRY(ccs->cme) : NULL)

RUBY_EXTERN bool ruby_box_enabled;
RUBY_EXTERN bool ruby_box_init_done;
RUBY_EXTERN bool ruby_box_crashed;

static inline bool
rb_box_available(void)
{
    return ruby_box_enabled;
}

const rb_box_t * rb_root_box(void);
const rb_box_t * rb_main_box(void);
const rb_box_t * rb_current_box(void);
const rb_box_t * rb_loading_box(void);
const rb_box_t * rb_current_box_in_crash_report(void);

void rb_box_entry_mark(void *);
void rb_box_gc_update_references(void *ptr);

rb_box_t * rb_get_box_t(VALUE ns);
VALUE rb_get_box_object(rb_box_t *ns);

VALUE rb_box_local_extension(VALUE box, VALUE fname, VALUE path, VALUE *cleanup);
void rb_box_cleanup_local_extension(VALUE cleanup);

void rb_initialize_main_box(void);
void rb_box_init_done(void);
#endif /* INTERNAL_BOX_H */
