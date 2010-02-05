#include "ruby.h"

/*
 * call-seq:
 *    fixnum.gcd(fixnum)  ->  fixnum
 *
 * Fixnum-specific optimized version of Integer#gcd.  Delegates to
 * Integer#gcd as necessary.
 */
static VALUE
fix_gcd(self, other)
    VALUE self, other;
{
    long a, b, min, max;

    /*
     * Note: Cannot handle values <= FIXNUM_MIN here due to overflow during negation.
     */
    if (!FIXNUM_P(other) ||
	(a = FIX2LONG(self)) <= FIXNUM_MIN ||
	(b = FIX2LONG(other)) <= FIXNUM_MIN ) {
	/* Delegate to Integer#gcd */
	return rb_call_super(1, &other);
    }

    min = a < 0 ? -a : a;
    max = b < 0 ? -b : b;

    while (min > 0) {
	long tmp = min;
	min = max % min;
	max = tmp;
    }

    return LONG2FIX(max);
}

void
Init_rational()
{
    rb_define_method(rb_cFixnum, "gcd", fix_gcd, 1);
}
