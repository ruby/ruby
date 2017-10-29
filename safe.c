/**********************************************************************

  safe.c -

  $Author$
  created at: Tue Sep 23 09:44:32 JST 2008

  Copyright (C) 2008 Yukihiro Matsumoto

**********************************************************************/

/* safe-level:
   0 - strings from streams/environment/ARGV are tainted (default)
   1 - no dangerous operation by tainted value
*/

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
    return 2;
}

int
rb_safe_level(void)
{
    return GET_EC()->safe_level;
}

void
rb_set_safe_level_force(int safe)
{
    GET_EC()->safe_level = safe;
}

void
rb_set_safe_level(int level)
{
    rb_execution_context_t *ec = GET_EC();

    if (level > ec->safe_level) {
	if (level > SAFE_LEVEL_MAX) {
	    rb_raise(rb_eArgError, "$SAFE=2 to 4 are obsolete");
	}
	/* block parameters */
	rb_vm_stack_to_heap(ec);

	ec->safe_level = level;
    }
}

static VALUE
safe_getter(void)
{
    return INT2NUM(rb_safe_level());
}

static void
safe_setter(VALUE val)
{
    rb_execution_context_t *ec = GET_EC();
    int current_level = ec->safe_level;
    int level = NUM2INT(val);

    if (level == current_level) {
	return;
    }
    else if (level < current_level) {
	rb_raise(rb_eSecurityError,
		 "tried to downgrade safe level from %d to %d",
		 current_level, level);
    }
    else if (level > SAFE_LEVEL_MAX) {
	rb_raise(rb_eArgError, "$SAFE=2 to 4 are obsolete");
    }

    /* block parameters */
    rb_vm_stack_to_heap(ec);

    ec->safe_level = level;
}

void
rb_secure(int level)
{
    if (level <= rb_safe_level()) {
	ID caller_name = rb_frame_callee();
	if (caller_name) {
	    rb_raise(rb_eSecurityError, "Insecure operation `%"PRIsVALUE"' at level %d",
		     rb_id2str(caller_name), rb_safe_level());
	}
	else {
	    rb_raise(rb_eSecurityError, "Insecure operation at level %d",
		     rb_safe_level());
	}
    }
}

void
rb_secure_update(VALUE obj)
{
}

void
rb_insecure_operation(void)
{
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
    if (rb_safe_level() > 0 && OBJ_TAINTED(x)) {
	rb_insecure_operation();
    }
}

void
Init_safe(void)
{
    rb_define_virtual_variable("$SAFE", safe_getter, safe_setter);
}
