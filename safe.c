/**********************************************************************

  safe.c -

  $Author$
  created at: Tue Sep 23 09:44:32 JST 2008

  Copyright (C) 2008 Yukihiro Matsumoto

**********************************************************************/

#define SAFE_LEVEL_MAX RUBY_SAFE_LEVEL_MAX

#include "ruby/ruby.h"
#include "vm_core.h"

/* $SAFE accessor */

#undef rb_secure
#undef rb_set_safe_level
#undef ruby_safe_level_2_warning

int
ruby_safe_level_2_warning(void)
{
    rb_warn("rb_safe_level_2_warning will be removed in Ruby 3.0");
    return 2;
}

int
rb_safe_level(void)
{
    rb_warn("rb_safe_level will be removed in Ruby 3.0");
    return GET_VM()->safe_level_;
}

void
rb_set_safe_level_force(int safe)
{
    rb_warn("rb_set_safe_level_force will be removed in Ruby 3.0");
    GET_VM()->safe_level_ = safe;
}

void
rb_set_safe_level(int level)
{
    rb_vm_t *vm = GET_VM();

    rb_warn("rb_set_safe_level will be removed in Ruby 3.0");
    if (level > SAFE_LEVEL_MAX) {
	rb_raise(rb_eArgError, "$SAFE=2 to 4 are obsolete");
    }
    else if (level < 0) {
	rb_raise(rb_eArgError, "$SAFE should be >= 0");
    }
    else {
	int line;
	const char *path = rb_source_location_cstr(&line);

	if (0) fprintf(stderr, "%s:%d $SAFE %d -> %d\n",
		       path ? path : "-", line, vm->safe_level_, level);

	vm->safe_level_ = level;
    }
}

static VALUE
safe_getter(ID _x, VALUE *_y)
{
    rb_warn("$SAFE will become a normal global variable in Ruby 3.0");
    return INT2NUM(GET_VM()->safe_level_);
}

static void
safe_setter(VALUE val, ID _x, VALUE *_y)
{
    int level = NUM2INT(val);
    rb_vm_t *vm = GET_VM();

    rb_warn("$SAFE will become a normal global variable in Ruby 3.0");
    if (level > SAFE_LEVEL_MAX) {
        rb_raise(rb_eArgError, "$SAFE=2 to 4 are obsolete");
    }
    else if (level < 0) {
        rb_raise(rb_eArgError, "$SAFE should be >= 0");
    }
    else {
        int line;
        const char *path = rb_source_location_cstr(&line);

        if (0) fprintf(stderr, "%s:%d $SAFE %d -> %d\n",
                       path ? path : "-", line, vm->safe_level_, level);

        vm->safe_level_ = level;
    }
}

void
rb_secure(int level)
{
    rb_warn("rb_secure will be removed in Ruby 3.0");
    if (level <= GET_VM()->safe_level_) {
	ID caller_name = rb_frame_callee();
	if (caller_name) {
	    rb_raise(rb_eSecurityError, "Insecure operation `%"PRIsVALUE"' at level %d",
                     rb_id2str(caller_name), GET_VM()->safe_level_);
	}
	else {
	    rb_raise(rb_eSecurityError, "Insecure operation at level %d",
                     GET_VM()->safe_level_);
	}
    }
}

void
rb_secure_update(VALUE obj)
{
    rb_warn("rb_secure_update will be removed in Ruby 3.0");
}

void
rb_insecure_operation(void)
{
    rb_warn("rb_insecure_operation will be removed in Ruby 3.0");
    ID caller_name = rb_frame_callee();
    if (caller_name) {
	rb_raise(rb_eSecurityError, "Insecure operation - %"PRIsVALUE,
		 rb_id2str(caller_name));
    }
    else {
	rb_raise(rb_eSecurityError, "Insecure operation: -r");
    }
}

void
rb_check_safe_obj(VALUE x)
{
    rb_warn("rb_check_safe_obj will be removed in Ruby 3.0");
}

void
Init_safe(void)
{
    rb_define_virtual_variable("$SAFE", safe_getter, safe_setter);
}
