/************************************************

  mandel.c -

  $Author$

************************************************/

#include "ruby.h"
#include "math.h"

static VALUE
mandel(self, re, im, max)
    VALUE self;
    VALUE re;
    VALUE im;
    VALUE max;
{
    double real, image;
    double z_real, z_image;
    double tmp_real;
    int maximum;
    int i;
	
    Check_Type(re, T_FLOAT);
    Check_Type(im, T_FLOAT);
    Check_Type(max, T_FIXNUM);

    real = RFLOAT(re)->value;
    image = RFLOAT(im)->value;
    maximum = FIX2INT(max);

    /***
    z = c = Complex(re, im)
    for i in 0 .. $max_deapth
      z = (z * z) + c
      break if z.abs > 2
    end
    return i
    ***/

    z_real = real;
    z_image = image;
    for (i = 0; i < maximum; i++) {
	tmp_real = ((z_real * z_real) - (z_image * z_image)) + real;
	z_image = ((z_real * z_image) + (z_image * z_real)) + image;
	z_real = tmp_real;
	if ( ((z_real * z_real) + (z_image * z_image)) > 4.0 ) {
	    break;
	}
    }
    return INT2FIX(i);
}

Init_mandel()
{
    VALUE mMandel = rb_define_module("Mandel");
    rb_define_module_function(mMandel, "mandel", mandel, 3);
}
