/**********************************************************************

  array.c -

  $Author$
  $Date$
  created at: Fri Aug  6 09:46:12 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include "util.h"
#include "st.h"

VALUE rb_cArray;
static ID id_cmp;

#define ARY_DEFAULT_SIZE 16
#define ARY_MAX_SIZE (LONG_MAX / sizeof(VALUE))

void
rb_mem_clear(mem, size)
    register VALUE *mem;
    register long size;
{
    while (size--) {
	*mem++ = Qnil;
    }
}

static inline void
memfill(mem, size, val)
    register VALUE *mem;
    register long size;
    register VALUE val;
{
    while (size--) {
	*mem++ = val;
    }
}

static void ary_double_capa _((VALUE, long));
static void
ary_double_capa(ary, min)
    VALUE ary;
    long min;
{
    long new_capa = RARRAY(ary)->aux.capa / 2;

    if (new_capa < ARY_DEFAULT_SIZE) {
	new_capa = ARY_DEFAULT_SIZE;
    }
    if (new_capa >= ARY_MAX_SIZE - min) {
	new_capa = (ARY_MAX_SIZE - min) / 2;
    }
    new_capa += min;
    REALLOC_N(RARRAY(ary)->ptr, VALUE, new_capa);
    RARRAY(ary)->aux.capa = new_capa;
}

#define ARY_TMPLOCK  FL_USER1

static inline void
rb_ary_modify_check(ary)
    VALUE ary;
{
    if (OBJ_FROZEN(ary)) rb_error_frozen("array");
    if (FL_TEST(ary, ARY_TMPLOCK))
	rb_raise(rb_eRuntimeError, "can't modify array during iteration");
    if (!OBJ_TAINTED(ary) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: can't modify array");
}

static void
rb_ary_modify(ary)
    VALUE ary;
{
    VALUE *ptr;

    rb_ary_modify_check(ary);
    if (FL_TEST(ary, ELTS_SHARED)) {
	ptr = ALLOC_N(VALUE, RARRAY(ary)->len);
	FL_UNSET(ary, ELTS_SHARED);
	RARRAY(ary)->aux.capa = RARRAY(ary)->len;
	MEMCPY(ptr, RARRAY(ary)->ptr, VALUE, RARRAY(ary)->len);
	RARRAY(ary)->ptr = ptr;
    }
}

VALUE
rb_ary_freeze(ary)
    VALUE ary;
{
    return rb_obj_freeze(ary);
}

/*
 *  call-seq:
 *     array.frozen?  -> true or false
 *
 *  Return <code>true</code> if this array is frozen (or temporarily frozen
 *  while being sorted).
 */

static VALUE
rb_ary_frozen_p(ary)
    VALUE ary;
{
    if (OBJ_FROZEN(ary)) return Qtrue;
    if (FL_TEST(ary, ARY_TMPLOCK)) return Qtrue;
    return Qfalse;
}

static VALUE ary_alloc _((VALUE));
static VALUE
ary_alloc(klass)
    VALUE klass;
{
    NEWOBJ(ary, struct RArray);
    OBJSETUP(ary, klass, T_ARRAY);

    ary->len = 0;
    ary->ptr = 0;
    ary->aux.capa = 0;

    return (VALUE)ary;
}

static VALUE
ary_new(klass, len)
    VALUE klass;
    long len;
{
    VALUE ary = ary_alloc(klass);

    if (len < 0) {
	rb_raise(rb_eArgError, "negative array size (or size too big)");
    }
    if (len > ARY_MAX_SIZE) {
	rb_raise(rb_eArgError, "array size too big");
    }
    if (len == 0) len++;
    RARRAY(ary)->ptr = ALLOC_N(VALUE, len);
    RARRAY(ary)->aux.capa = len;

    return ary;
}

VALUE
rb_ary_new2(len)
    long len;
{
    return ary_new(rb_cArray, len);
}


VALUE
rb_ary_new()
{
    return rb_ary_new2(ARY_DEFAULT_SIZE);
}

#ifdef HAVE_STDARG_PROTOTYPES
#include <stdarg.h>
#define va_init_list(a,b) va_start(a,b)
#else
#include <varargs.h>
#define va_init_list(a,b) va_start(a)
#endif

VALUE
#ifdef HAVE_STDARG_PROTOTYPES
rb_ary_new3(long n, ...)
#else
rb_ary_new3(n, va_alist)
    long n;
    va_dcl
#endif
{
    va_list ar;
    VALUE ary;
    long i;

    ary = rb_ary_new2(n);

    va_init_list(ar, n);
    for (i=0; i<n; i++) {
	RARRAY(ary)->ptr[i] = va_arg(ar, VALUE);
    }
    va_end(ar);

    RARRAY(ary)->len = n;
    return ary;
}

VALUE
rb_ary_new4(n, elts)
    long n;
    const VALUE *elts;
{
    VALUE ary;

    ary = rb_ary_new2(n);
    if (n > 0 && elts) {
	MEMCPY(RARRAY(ary)->ptr, elts, VALUE, n);
    }

    /* This assignment to len will be moved to the above "if" block in Ruby 1.9 */
    RARRAY(ary)->len = n;

    return ary;
}

static VALUE
ary_make_shared(ary)
    VALUE ary;
{
    if (!FL_TEST(ary, ELTS_SHARED)) {
	NEWOBJ(shared, struct RArray);
	OBJSETUP(shared, rb_cArray, T_ARRAY);

	shared->len = RARRAY(ary)->len;
	shared->ptr = RARRAY(ary)->ptr;
	shared->aux.capa = RARRAY(ary)->aux.capa;
	RARRAY(ary)->aux.shared = (VALUE)shared;
	FL_SET(ary, ELTS_SHARED);
	OBJ_FREEZE(shared);
	return (VALUE)shared;
    }
    else {
	return RARRAY(ary)->aux.shared;
    }
}

VALUE
rb_assoc_new(car, cdr)
    VALUE car, cdr;
{
    VALUE ary;

    ary = rb_ary_new2(2);
    RARRAY(ary)->ptr[0] = car;
    RARRAY(ary)->ptr[1] = cdr;
    RARRAY(ary)->len = 2;

    return ary;
}

static VALUE
to_ary(ary)
    VALUE ary;
{
    return rb_convert_type(ary, T_ARRAY, "Array", "to_ary");
}

VALUE
rb_check_array_type(ary)
    VALUE ary;
{
    return rb_check_convert_type(ary, T_ARRAY, "Array", "to_ary");
}

/*
 *  call-seq:
 *     Array.try_convert(obj) -> array or nil
 *
 *  Try to convert <i>obj</i> into an array, using to_ary method.
 *  Returns converted array or nil if <i>obj</i> cannot be converted
 *  for any reason.  This method is to check if an argument is an
 *  array.
 *
 *     Array.try_convert([1])   # => [1]
 *     Array.try_convert("1")   # => nil
 *
 *     if tmp = Array.try_convert(arg)
 *       # the argument is an array
 *     elsif tmp = String.try_convert(arg)
 *       # the argument is a string
 *     end
 *
 */

static VALUE
rb_ary_s_try_convert(dummy, ary)
    VALUE dummy, ary;
{
    return rb_check_array_type(ary);
}

static VALUE rb_ary_replace _((VALUE, VALUE));

/*
 *  call-seq:
 *     Array.new(size=0, obj=nil)
 *     Array.new(array)
 *     Array.new(size) {|index| block }
 *
 *  Returns a new array. In the first form, the new array is
 *  empty. In the second it is created with _size_ copies of _obj_
 *  (that is, _size_ references to the same
 *  _obj_). The third form creates a copy of the array
 *  passed as a parameter (the array is generated by calling
 *  to_ary  on the parameter). In the last form, an array
 *  of the given size is created. Each element in this array is
 *  calculated by passing the element's index to the given block and
 *  storing the return value.
 *
 *     Array.new
 *     Array.new(2)
 *     Array.new(5, "A")
 *
 *     # only one copy of the object is created
 *     a = Array.new(2, Hash.new)
 *     a[0]['cat'] = 'feline'
 *     a
 *     a[1]['cat'] = 'Felix'
 *     a
 *
 *     # here multiple copies are created
 *     a = Array.new(2) { Hash.new }
 *     a[0]['cat'] = 'feline'
 *     a
 *
 *     squares = Array.new(5) {|i| i*i}
 *     squares
 *
 *     copy = Array.new(squares)
 */

static VALUE
rb_ary_initialize(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    long len;
    VALUE size, val;

    rb_ary_modify(ary);
    if (rb_scan_args(argc, argv, "02", &size, &val) == 0) {
	RARRAY(ary)->len = 0;
	if (rb_block_given_p()) {
	    rb_warning("given block not used");
	}
	return ary;
    }

    if (argc == 1 && !FIXNUM_P(size)) {
	val = rb_check_array_type(size);
	if (!NIL_P(val)) {
	    rb_ary_replace(ary, val);
	    return ary;
	}
    }

    len = NUM2LONG(size);
    if (len < 0) {
	rb_raise(rb_eArgError, "negative array size");
    }
    if (len > ARY_MAX_SIZE) {
	rb_raise(rb_eArgError, "array size too big");
    }
    if (len > RARRAY(ary)->aux.capa) {
	REALLOC_N(RARRAY(ary)->ptr, VALUE, len);
	RARRAY(ary)->aux.capa = len;
    }
    if (rb_block_given_p()) {
	long i;

	if (argc == 2) {
	    rb_warn("block supersedes default value argument");
	}
	for (i=0; i<len; i++) {
	    rb_ary_store(ary, i, rb_yield(LONG2NUM(i)));
	    RARRAY(ary)->len = i + 1;
	}
    }
    else {
	memfill(RARRAY(ary)->ptr, len, val);
	RARRAY(ary)->len = len;
    }

    return ary;
}


/*
* Returns a new array populated with the given objects.
*
*   Array.[]( 1, 'a', /^A/ )
*   Array[ 1, 'a', /^A/ ]
*   [ 1, 'a', /^A/ ]
*/

static VALUE
rb_ary_s_create(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE ary = ary_alloc(klass);

    if (argc > 0) {
	RARRAY(ary)->ptr = ALLOC_N(VALUE, argc);
	MEMCPY(RARRAY(ary)->ptr, argv, VALUE, argc);
    }
    RARRAY(ary)->len = RARRAY(ary)->aux.capa = argc;

    return ary;
}

void
rb_ary_store(ary, idx, val)
    VALUE ary;
    long idx;
    VALUE val;
{
    if (idx < 0) {
	idx += RARRAY(ary)->len;
	if (idx < 0) {
	    rb_raise(rb_eIndexError, "index %ld out of array",
		    idx - RARRAY(ary)->len);
	}
    }
    else if (idx >= ARY_MAX_SIZE) {
	rb_raise(rb_eIndexError, "index %ld too big", idx);
    }

    rb_ary_modify(ary);
    if (idx >= RARRAY(ary)->aux.capa) {
	ary_double_capa(ary, idx);
    }
    if (idx > RARRAY(ary)->len) {
	rb_mem_clear(RARRAY(ary)->ptr + RARRAY(ary)->len,
		     idx-RARRAY(ary)->len + 1);
    }

    if (idx >= RARRAY(ary)->len) {
	RARRAY(ary)->len = idx + 1;
    }
    RARRAY(ary)->ptr[idx] = val;
}

static VALUE
ary_shared_array(klass, ary)
    VALUE klass;
    VALUE ary;
{
    VALUE val = ary_alloc(klass);

    ary_make_shared(ary);
    RARRAY(val)->ptr = RARRAY(ary)->ptr;
    RARRAY(val)->len = RARRAY(ary)->len;
    RARRAY(val)->aux.shared = RARRAY(ary)->aux.shared;
    FL_SET(val, ELTS_SHARED);
    return val;
}

static VALUE
ary_shared_first(argc, argv, ary, last)
    int argc;
    VALUE *argv;
    VALUE ary;
    int last;
{
    VALUE nv, result;
    long n;
    long offset = 0;

    rb_scan_args(argc, argv, "1", &nv);
    n = NUM2LONG(nv);
    if (n > RARRAY(ary)->len) {
	n = RARRAY(ary)->len;
    }
    else if (n < 0) {
	rb_raise(rb_eArgError, "negative array size");
    }
    if (last) {
	offset = RARRAY(ary)->len - n;
    }
    result = ary_shared_array(rb_cArray, ary);
    RARRAY(result)->ptr += offset;
    RARRAY(result)->len = n;

    return result;
}

/*
 *  call-seq:
 *     array << obj            -> array
 *
 *  Append---Pushes the given object on to the end of this array. This
 *  expression returns the array itself, so several appends
 *  may be chained together.
 *
 *     [ 1, 2 ] << "c" << "d" << [ 3, 4 ]
 *             #=>  [ 1, 2, "c", "d", [ 3, 4 ] ]
 *
 */

VALUE
rb_ary_push(ary, item)
    VALUE ary;
    VALUE item;
{
    rb_ary_store(ary, RARRAY(ary)->len, item);
    return ary;
}

/*
 *  call-seq:
 *     array.push(obj, ... )   -> array
 *
 *  Append---Pushes the given object(s) on to the end of this array. This
 *  expression returns the array itself, so several appends
 *  may be chained together.
 *
 *     a = [ "a", "b", "c" ]
 *     a.push("d", "e", "f")
 *             #=> ["a", "b", "c", "d", "e", "f"]
 */

static VALUE
rb_ary_push_m(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    while (argc--) {
	rb_ary_push(ary, *argv++);
    }
    return ary;
}

VALUE
rb_ary_pop(ary)
    VALUE ary;
{
    rb_ary_modify_check(ary);
    if (RARRAY(ary)->len == 0) return Qnil;
    if (!FL_TEST(ary, ELTS_SHARED) &&
	    RARRAY(ary)->len * 3 < RARRAY(ary)->aux.capa &&
	    RARRAY(ary)->aux.capa > ARY_DEFAULT_SIZE) {
	RARRAY(ary)->aux.capa = RARRAY(ary)->len * 2;
	REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->aux.capa);
    }
    return RARRAY(ary)->ptr[--RARRAY(ary)->len];
}

/*
 *  call-seq:
 *     array.pop    -> obj or nil
 *     array.pop(n) -> array
 *
 *  Removes the last element from <i>self</i> and returns it, or
 *  <code>nil</code> if the array is empty.
 *
 *  If a number _n_ is given, returns an array of the last n elements
 *  (or less) just like <code>array.slice!(-n, n)</code> does.
 *
 *     a = [ "a", "b", "c", "d" ]
 *     a.pop     #=> "d"
 *     a.pop(2)  #=> ["b", "c"]
 *     a         #=> ["a"]
 */

static VALUE
rb_ary_pop_m(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE result;

    if (argc == 0) {
	return rb_ary_pop(ary);
    }

    rb_ary_modify_check(ary);
    result = ary_shared_first(argc, argv, ary, Qtrue);
    RARRAY(ary)->len -= RARRAY(result)->len;
    return result;
}

VALUE
rb_ary_shift(ary)
    VALUE ary;
{
    VALUE top;

    rb_ary_modify_check(ary);
    if (RARRAY(ary)->len == 0) return Qnil;
    top = RARRAY(ary)->ptr[0];
    if (!FL_TEST(ary, ELTS_SHARED)) {
        if (RARRAY(ary)->len < ARY_DEFAULT_SIZE) {
            MEMMOVE(RARRAY(ary)->ptr, RARRAY(ary)->ptr+1, VALUE, RARRAY(ary)->len-1);
	    RARRAY(ary)->len--;
            return top;
        }
        RARRAY(ary)->ptr[0] = Qnil;
	ary_make_shared(ary);
    }
    RARRAY(ary)->ptr++;		/* shift ptr */
    RARRAY(ary)->len--;

    return top;
}

/*
 *  call-seq:
 *     array.shift    -> obj or nil
 *     array.shift(n) -> array
 *
 *  Returns the first element of <i>self</i> and removes it (shifting all
 *  other elements down by one). Returns <code>nil</code> if the array
 *  is empty.
 *
 *  If a number _n_ is given, returns an array of the first n elements
 *  (or less) just like <code>array.slice!(0, n)</code> does.
 *
 *     args = [ "-m", "-q", "filename" ]
 *     args.shift     #=> "-m"
 *     args           #=> ["-q", "filename"]
 *
 *     args = [ "-m", "-q", "filename" ]
 *     args.shift(2)  #=> ["-m", "-q"]
 *     args           #=> ["filename"]
 */

static VALUE
rb_ary_shift_m(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE result;
    long n;

    if (argc == 0) {
	return rb_ary_shift(ary);
    }

    rb_ary_modify_check(ary);
    result = ary_shared_first(argc, argv, ary, Qfalse);
    n = RARRAY(result)->len;
    if (FL_TEST(ary, ELTS_SHARED)) {
	RARRAY(ary)->ptr += n;
	RARRAY(ary)->len -= n;
	}
    else {
	MEMMOVE(RARRAY(ary)->ptr, RARRAY(ary)->ptr+n, VALUE, RARRAY(ary)->len-n);
	RARRAY(ary)->len -= n;
    }

    return result;
}

VALUE
rb_ary_unshift(ary, item)
    VALUE ary, item;
{
    rb_ary_modify(ary);
    if (RARRAY(ary)->len == RARRAY(ary)->aux.capa) {
	long capa_inc = RARRAY(ary)->aux.capa / 2;
	if (capa_inc < ARY_DEFAULT_SIZE) {
	    capa_inc = ARY_DEFAULT_SIZE;
	}
	RARRAY(ary)->aux.capa += capa_inc;
	REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->aux.capa);
    }

    /* sliding items */
    MEMMOVE(RARRAY(ary)->ptr + 1, RARRAY(ary)->ptr, VALUE, RARRAY(ary)->len);

    RARRAY(ary)->len++;
    RARRAY(ary)->ptr[0] = item;

    return ary;
}

/*
 *  call-seq:
 *     array.unshift(obj, ...)  -> array
 *
 *  Prepends objects to the front of <i>array</i>.
 *  other elements up one.
 *
 *     a = [ "b", "c", "d" ]
 *     a.unshift("a")   #=> ["a", "b", "c", "d"]
 *     a.unshift(1, 2)  #=> [ 1, 2, "a", "b", "c", "d"]
 */

static VALUE
rb_ary_unshift_m(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    long len = RARRAY(ary)->len;

    if (argc == 0) return ary;

    /* make rooms by setting the last item */
    rb_ary_store(ary, len + argc - 1, Qnil);

    /* sliding items */
    MEMMOVE(RARRAY(ary)->ptr + argc, RARRAY(ary)->ptr, VALUE, len);
    MEMCPY(RARRAY(ary)->ptr, argv, VALUE, argc);

    return ary;
}

/* faster version - use this if you don't need to treat negative offset */
static inline VALUE
rb_ary_elt(ary, offset)
    VALUE ary;
    long offset;
{
    if (RARRAY(ary)->len == 0) return Qnil;
    if (offset < 0 || RARRAY(ary)->len <= offset) {
	return Qnil;
    }
    return RARRAY(ary)->ptr[offset];
}

VALUE
rb_ary_entry(ary, offset)
    VALUE ary;
    long offset;
{
    if (offset < 0) {
	offset += RARRAY(ary)->len;
    }
    return rb_ary_elt(ary, offset);
}

static VALUE
rb_ary_subseq(ary, beg, len)
    VALUE ary;
    long beg, len;
{
    VALUE klass, ary2, shared;
    VALUE *ptr;

    if (beg > RARRAY(ary)->len) return Qnil;
    if (beg < 0 || len < 0) return Qnil;

    if (RARRAY(ary)->len < len || RARRAY(ary)->len < beg + len) {
	len = RARRAY(ary)->len - beg;
	if (len < 0)
	    len = 0;
    }
    klass = rb_obj_class(ary);
    if (len == 0) return ary_new(klass, 0);

    shared = ary_make_shared(ary);
    ptr = RARRAY(ary)->ptr;
    ary2 = ary_alloc(klass);
    RARRAY(ary2)->ptr = ptr + beg;
    RARRAY(ary2)->len = len;
    RARRAY(ary2)->aux.shared = shared;
    FL_SET(ary2, ELTS_SHARED);

    return ary2;
}

/*
 *  call-seq:
 *     array[index]                -> obj      or nil
 *     array[start, length]        -> an_array or nil
 *     array[range]                -> an_array or nil
 *     array.slice(index)          -> obj      or nil
 *     array.slice(start, length)  -> an_array or nil
 *     array.slice(range)          -> an_array or nil
 *
 *  Element Reference---Returns the element at _index_,
 *  or returns a subarray starting at _start_ and
 *  continuing for _length_ elements, or returns a subarray
 *  specified by _range_.
 *  Negative indices count backward from the end of the
 *  array (-1 is the last element). Returns nil if the index
 *  (or starting index) are out of range.
 *
 *     a = [ "a", "b", "c", "d", "e" ]
 *     a[2] +  a[0] + a[1]    #=> "cab"
 *     a[6]                   #=> nil
 *     a[1, 2]                #=> [ "b", "c" ]
 *     a[1..3]                #=> [ "b", "c", "d" ]
 *     a[4..7]                #=> [ "e" ]
 *     a[6..10]               #=> nil
 *     a[-3, 3]               #=> [ "c", "d", "e" ]
 *     # special cases
 *     a[5]                   #=> nil
 *     a[5, 1]                #=> []
 *     a[5..10]               #=> []
 *
 */

VALUE
rb_ary_aref(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE arg;
    long beg, len;

    if (argc == 2) {
	if (SYMBOL_P(argv[0])) {
	    rb_raise(rb_eTypeError, "Symbol as array index");
	}
	beg = NUM2LONG(argv[0]);
	len = NUM2LONG(argv[1]);
	if (beg < 0) {
	    beg += RARRAY(ary)->len;
	}
	return rb_ary_subseq(ary, beg, len);
    }
    if (argc != 1) {
	rb_scan_args(argc, argv, "11", 0, 0);
    }
    arg = argv[0];
    /* special case - speeding up */
    if (FIXNUM_P(arg)) {
	return rb_ary_entry(ary, FIX2LONG(arg));
    }
    if (SYMBOL_P(arg)) {
	rb_raise(rb_eTypeError, "Symbol as array index");
    }
    /* check if idx is Range */
    switch (rb_range_beg_len(arg, &beg, &len, RARRAY(ary)->len, 0)) {
      case Qfalse:
	break;
      case Qnil:
	return Qnil;
      default:
	return rb_ary_subseq(ary, beg, len);
    }
    return rb_ary_entry(ary, NUM2LONG(arg));
}

/*
 *  call-seq:
 *     array.at(index)   ->   obj  or nil
 *
 *  Returns the element at _index_. A
 *  negative index counts from the end of _self_.  Returns +nil+
 *  if the index is out of range. See also <code>Array#[]</code>.
 *  (<code>Array#at</code> is slightly faster than <code>Array#[]</code>,
 *  as it does not accept ranges and so on.)
 *
 *     a = [ "a", "b", "c", "d", "e" ]
 *     a.at(0)     #=> "a"
 *     a.at(-1)    #=> "e"
 */

static VALUE
rb_ary_at(ary, pos)
    VALUE ary, pos;
{
    return rb_ary_entry(ary, NUM2LONG(pos));
}

/*
 *  call-seq:
 *     array.first   ->   obj or nil
 *     array.first(n) -> an_array
 *
 *  Returns the first element, or the first +n+ elements, of the array.
 *  If the array is empty, the first form returns <code>nil</code>, and the
 *  second form returns an empty array.
 *
 *     a = [ "q", "r", "s", "t" ]
 *     a.first    #=> "q"
 *     a.first(1) #=> ["q"]
 *     a.first(3) #=> ["q", "r", "s"]
 */

static VALUE
rb_ary_first(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    if (argc == 0) {
	if (RARRAY(ary)->len == 0) return Qnil;
	return RARRAY(ary)->ptr[0];
    }
    else {
	return ary_shared_first(argc, argv, ary, Qfalse);
    }
}

/*
 *  call-seq:
 *     array.last     ->  obj or nil
 *     array.last(n)  ->  an_array
 *
 *  Returns the last element(s) of <i>self</i>. If the array is empty,
 *  the first form returns <code>nil</code>.
 *
 *     [ "w", "x", "y", "z" ].last   #=> "z"
 */

static VALUE
rb_ary_last(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    if (argc == 0) {
	if (RARRAY(ary)->len == 0) return Qnil;
	return RARRAY(ary)->ptr[RARRAY(ary)->len-1];
    }
    else {
	return ary_shared_first(argc, argv, ary, Qtrue);
    }
}

/*
 *  call-seq:
 *     array.fetch(index)                    -> obj
 *     array.fetch(index, default )          -> obj
 *     array.fetch(index) {|index| block }   -> obj
 *
 *  Tries to return the element at position <i>index</i>. If the index
 *  lies outside the array, the first form throws an
 *  <code>IndexError</code> exception, the second form returns
 *  <i>default</i>, and the third form returns the value of invoking
 *  the block, passing in the index. Negative values of <i>index</i>
 *  count from the end of the array.
 *
 *     a = [ 11, 22, 33, 44 ]
 *     a.fetch(1)               #=> 22
 *     a.fetch(-1)              #=> 44
 *     a.fetch(4, 'cat')        #=> "cat"
 *     a.fetch(4) { |i| i*i }   #=> 16
 */

static VALUE
rb_ary_fetch(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE pos, ifnone;
    long block_given;
    long idx;

    rb_scan_args(argc, argv, "11", &pos, &ifnone);
    block_given = rb_block_given_p();
    if (block_given && argc == 2) {
	rb_warn("block supersedes default value argument");
    }
    idx = NUM2LONG(pos);

    if (idx < 0) {
	idx +=  RARRAY(ary)->len;
    }
    if (idx < 0 || RARRAY(ary)->len <= idx) {
	if (block_given) return rb_yield(pos);
	if (argc == 1) {
	    rb_raise(rb_eIndexError, "index %ld out of array", idx);
	}
	return ifnone;
    }
    return RARRAY(ary)->ptr[idx];
}

/*
 *  call-seq:
 *     array.index(obj)           ->  int or nil
 *     array.index {|item| block} ->  int or nil
 *
 *  Returns the index of the first object in <i>self</i> such that is
 *  <code>==</code> to <i>obj</i>. If a block is given instead of an
 *  argument, returns first object for which <em>block</em> is true.
 *  Returns <code>nil</code> if no match is found.
 *
 *     a = [ "a", "b", "c" ]
 *     a.index("b")        #=> 1
 *     a.index("z")        #=> nil
 *     a.index{|x|x=="b"}  #=> 1
 *
 *  This is an alias of <code>#find_index</code>.
 */

static VALUE
rb_ary_index(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE val;
    long i;

    if (argc  == 0) {
	RETURN_ENUMERATOR(ary, 0, 0);
	for (i=0; i<RARRAY(ary)->len; i++) {
	    if (RTEST(rb_yield(RARRAY(ary)->ptr[i]))) {
		return LONG2NUM(i);
	    }
	}
	return Qnil;
    }
    rb_scan_args(argc, argv, "01", &val);
    for (i=0; i<RARRAY(ary)->len; i++) {
	if (rb_equal(RARRAY(ary)->ptr[i], val))
	    return LONG2NUM(i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     array.rindex(obj)    ->  int or nil
 *
 *  Returns the index of the last object in <i>array</i>
 *  <code>==</code> to <i>obj</i>. If a block is given instead of an
 *  argument, returns first object for which <em>block</em> is
 *  true. Returns <code>nil</code> if no match is found.
 *
 *     a = [ "a", "b", "b", "b", "c" ]
 *     a.rindex("b")        #=> 3
 *     a.rindex("z")        #=> nil
 *     a.rindex{|x|x=="b"}  #=> 3
 */

static VALUE
rb_ary_rindex(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE val;
    long i = RARRAY(ary)->len;

    if (argc == 0) {
	RETURN_ENUMERATOR(ary, 0, 0);
	while (i--) {
	    if (RTEST(rb_yield(RARRAY(ary)->ptr[i])))
		return LONG2NUM(i);
	    if (i > RARRAY(ary)->len) {
		i = RARRAY(ary)->len;
	    }
	}
	return Qnil;
    }
    rb_scan_args(argc, argv, "01", &val);
    while (i--) {
	if (rb_equal(RARRAY(ary)->ptr[i], val))
	    return LONG2NUM(i);
	if (i > RARRAY(ary)->len) {
	    i = RARRAY(ary)->len;
	}
    }
    return Qnil;
}

/*
 *  call-seq:
 *     array.indexes( i1, i2, ... iN )   -> an_array
 *     array.indices( i1, i2, ... iN )   -> an_array
 *
 *  Deprecated; use <code>Array#values_at</code>.
 */

static VALUE
rb_ary_indexes(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE new_ary;
    long i;

    rb_warn("Array#%s is deprecated; use Array#values_at", rb_id2name(rb_frame_last_func()));
    new_ary = rb_ary_new2(argc);
    for (i=0; i<argc; i++) {
	rb_ary_push(new_ary, rb_ary_aref(1, argv+i, ary));
    }

    return new_ary;
}

VALUE
rb_ary_to_ary(obj)
    VALUE obj;
{
    if (TYPE(obj) == T_ARRAY) {
	return obj;
    }
    if (rb_respond_to(obj, rb_intern("to_ary"))) {
	return rb_convert_type(obj, T_ARRAY, "Array", "to_ary");
    }
    return rb_ary_new3(1, obj);
}

static void
rb_ary_splice(ary, beg, len, rpl)
    VALUE ary;
    long beg, len;
    VALUE rpl;
{
    long rlen;

    if (len < 0) rb_raise(rb_eIndexError, "negative length (%ld)", len);
    if (beg < 0) {
	beg += RARRAY(ary)->len;
	if (beg < 0) {
	    beg -= RARRAY(ary)->len;
	    rb_raise(rb_eIndexError, "index %ld out of array", beg);
	}
    }
    if (RARRAY(ary)->len < len || RARRAY(ary)->len < beg + len) {
	len = RARRAY(ary)->len - beg;
    }

    if (NIL_P(rpl)) {
	rlen = 0;
    }
    else {
	rpl = rb_ary_to_ary(rpl);
	rlen = RARRAY(rpl)->len;
    }
    rb_ary_modify(ary);

    if (beg >= RARRAY(ary)->len) {
	if (beg > ARY_MAX_SIZE - rlen) {
	    rb_raise(rb_eIndexError, "index %ld too big", beg);
	}
	len = beg + rlen;
	if (len >= RARRAY(ary)->aux.capa) {
	    ary_double_capa(ary, len);
	}
	rb_mem_clear(RARRAY(ary)->ptr + RARRAY(ary)->len, beg - RARRAY(ary)->len);
	if (rlen > 0) {
	    MEMCPY(RARRAY(ary)->ptr + beg, RARRAY(rpl)->ptr, VALUE, rlen);
	}
	RARRAY(ary)->len = len;
    }
    else {
	long alen;

	if (beg + len > RARRAY(ary)->len) {
	    len = RARRAY(ary)->len - beg;
	}

	alen = RARRAY(ary)->len + rlen - len;
	if (alen >= RARRAY(ary)->aux.capa) {
	    REALLOC_N(RARRAY(ary)->ptr, VALUE, alen);
	    RARRAY(ary)->aux.capa = alen;
	}

	if (len != rlen) {
	    MEMMOVE(RARRAY(ary)->ptr + beg + rlen, RARRAY(ary)->ptr + beg + len,
		    VALUE, RARRAY(ary)->len - (beg + len));
	    RARRAY(ary)->len = alen;
	}
	if (rlen > 0) {
	    MEMMOVE(RARRAY(ary)->ptr + beg, RARRAY(rpl)->ptr, VALUE, rlen);
	}
    }
}

/*
 *  call-seq:
 *     array[index]         = obj                     ->  obj
 *     array[start, length] = obj or an_array or nil  ->  obj or an_array or nil
 *     array[range]         = obj or an_array or nil  ->  obj or an_array or nil
 *
 *  Element Assignment---Sets the element at _index_,
 *  or replaces a subarray starting at _start_ and
 *  continuing for _length_ elements, or replaces a subarray
 *  specified by _range_.  If indices are greater than
 *  the current capacity of the array, the array grows
 *  automatically. A negative indices will count backward
 *  from the end of the array. Inserts elements if _length_ is
 *  zero. If +nil+ is used in the second and third form,
 *  deletes elements from _self_. An +IndexError+ is raised if a
 *  negative index points past the beginning of the array. See also
 *  <code>Array#push</code>, and <code>Array#unshift</code>.
 *
 *     a = Array.new
 *     a[4] = "4";                 #=> [nil, nil, nil, nil, "4"]
 *     a[0, 3] = [ 'a', 'b', 'c' ] #=> ["a", "b", "c", nil, "4"]
 *     a[1..2] = [ 1, 2 ]          #=> ["a", 1, 2, nil, "4"]
 *     a[0, 2] = "?"               #=> ["?", 2, nil, "4"]
 *     a[0..2] = "A"               #=> ["A", "4"]
 *     a[-1]   = "Z"               #=> ["A", "Z"]
 *     a[1..-1] = nil              #=> ["A"]
 */

static VALUE
rb_ary_aset(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    long offset, beg, len;

    if (argc == 3) {
	if (SYMBOL_P(argv[0])) {
	    rb_raise(rb_eTypeError, "Symbol as array index");
	}
	if (SYMBOL_P(argv[1])) {
	    rb_raise(rb_eTypeError, "Symbol as subarray length");
	}
	beg = NUM2LONG(argv[0]);
	len = NUM2LONG(argv[1]);
	rb_ary_splice(ary, beg, len, argv[2]);
	return argv[2];
    }
    if (argc != 2) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 2)", argc);
    }
    if (FIXNUM_P(argv[0])) {
	offset = FIX2LONG(argv[0]);
	goto fixnum;
    }
    if (SYMBOL_P(argv[0])) {
	rb_raise(rb_eTypeError, "Symbol as array index");
    }
    if (rb_range_beg_len(argv[0], &beg, &len, RARRAY(ary)->len, 1)) {
	/* check if idx is Range */
	rb_ary_splice(ary, beg, len, argv[1]);
	return argv[1];
    }

    offset = NUM2LONG(argv[0]);
fixnum:
    rb_ary_store(ary, offset, argv[1]);
    return argv[1];
}

/*
 *  call-seq:
 *     array.insert(index, obj...)  -> array
 *
 *  Inserts the given values before the element with the given index
 *  (which may be negative).
 *
 *     a = %w{ a b c d }
 *     a.insert(2, 99)         #=> ["a", "b", 99, "c", "d"]
 *     a.insert(-2, 1, 2, 3)   #=> ["a", "b", 99, "c", 1, 2, 3, "d"]
 */

static VALUE
rb_ary_insert(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    long pos;

    if (argc == 1) return ary;
    if (argc < 1) {
	rb_raise(rb_eArgError, "wrong number of arguments (at least 1)");
    }
    pos = NUM2LONG(argv[0]);
    if (pos == -1) {
	pos = RARRAY(ary)->len;
    }
    if (pos < 0) {
	pos++;
    }
    rb_ary_splice(ary, pos, 0, rb_ary_new4(argc - 1, argv + 1));
    return ary;
}

/*
 *  call-seq:
 *     array.each {|item| block }   ->   array
 *
 *  Calls <i>block</i> once for each element in <i>self</i>, passing that
 *  element as a parameter.
 *
 *     a = [ "a", "b", "c" ]
 *     a.each {|x| print x, " -- " }
 *
 *  produces:
 *
 *     a -- b -- c --
 */

VALUE
rb_ary_each(ary)
    VALUE ary;
{
    long i;

    RETURN_ENUMERATOR(ary, 0, 0);
    for (i=0; i<RARRAY(ary)->len; i++) {
	rb_yield(RARRAY(ary)->ptr[i]);
    }
    return ary;
}

/*
 *  call-seq:
 *     array.each_index {|index| block }  ->  array
 *
 *  Same as <code>Array#each</code>, but passes the index of the element
 *  instead of the element itself.
 *
 *     a = [ "a", "b", "c" ]
 *     a.each_index {|x| print x, " -- " }
 *
 *  produces:
 *
 *     0 -- 1 -- 2 --
 */

static VALUE
rb_ary_each_index(ary)
    VALUE ary;
{
    long i;

    RETURN_ENUMERATOR(ary, 0, 0);
    for (i=0; i<RARRAY(ary)->len; i++) {
	rb_yield(LONG2NUM(i));
    }
    return ary;
}

/*
 *  call-seq:
 *     array.reverse_each {|item| block }
 *
 *  Same as <code>Array#each</code>, but traverses <i>self</i> in reverse
 *  order.
 *
 *     a = [ "a", "b", "c" ]
 *     a.reverse_each {|x| print x, " " }
 *
 *  produces:
 *
 *     c b a
 */

static VALUE
rb_ary_reverse_each(ary)
    VALUE ary;
{
    long len;

    RETURN_ENUMERATOR(ary, 0, 0);
    len = RARRAY(ary)->len;
    while (len--) {
	rb_yield(RARRAY(ary)->ptr[len]);
	if (RARRAY(ary)->len < len) {
	    len = RARRAY(ary)->len;
	}
    }
    return ary;
}

/*
 *  call-seq:
 *     array.length -> int
 *
 *  Returns the number of elements in <i>self</i>. May be zero.
 *
 *     [ 1, 2, 3, 4, 5 ].length   #=> 5
 */

static VALUE
rb_ary_length(ary)
    VALUE ary;
{
    return LONG2NUM(RARRAY(ary)->len);
}

/*
 *  call-seq:
 *     array.empty?   -> true or false
 *
 *  Returns <code>true</code> if <i>self</i> array contains no elements.
 *
 *     [].empty?   #=> true
 */

static VALUE
rb_ary_empty_p(ary)
    VALUE ary;
{
    if (RARRAY(ary)->len == 0)
	return Qtrue;
    return Qfalse;
}

VALUE
rb_ary_dup(ary)
    VALUE ary;
{
    VALUE dup = rb_ary_new2(RARRAY(ary)->len);

    DUPSETUP(dup, ary);
    MEMCPY(RARRAY(dup)->ptr, RARRAY(ary)->ptr, VALUE, RARRAY(ary)->len);
    RARRAY(dup)->len = RARRAY(ary)->len;
    return dup;
}

extern VALUE rb_output_fs;

static VALUE
inspect_join(ary, arg)
    VALUE ary;
    VALUE *arg;
{
    return rb_ary_join(arg[0], arg[1]);
}

VALUE
rb_ary_join(ary, sep)
    VALUE ary, sep;
{
    long len = 1, i;
    int taint = Qfalse;
    VALUE result, tmp;

    if (RARRAY(ary)->len == 0) return rb_str_new(0, 0);
    if (OBJ_TAINTED(ary) || OBJ_TAINTED(sep)) taint = Qtrue;

    for (i=0; i<RARRAY(ary)->len; i++) {
	tmp = rb_check_string_type(RARRAY(ary)->ptr[i]);
	len += NIL_P(tmp) ? 10 : RSTRING(tmp)->len;
    }
    if (!NIL_P(sep)) {
	StringValue(sep);
	len += RSTRING(sep)->len * (RARRAY(ary)->len - 1);
    }
    result = rb_str_buf_new(len);
    for (i=0; i<RARRAY(ary)->len; i++) {
	tmp = RARRAY(ary)->ptr[i];
	switch (TYPE(tmp)) {
	  case T_STRING:
	    break;
	  case T_ARRAY:
	    if (tmp == ary || rb_inspecting_p(tmp)) {
		tmp = rb_str_new2("[...]");
	    }
	    else {
		VALUE args[2];

		args[0] = tmp;
		args[1] = sep;
		tmp = rb_protect_inspect(inspect_join, ary, (VALUE)args);
	    }
	    break;
	  default:
	    tmp = rb_obj_as_string(tmp);
	}
	if (i > 0 && !NIL_P(sep))
	    rb_str_buf_append(result, sep);
	rb_str_buf_append(result, tmp);
	if (OBJ_TAINTED(tmp)) taint = Qtrue;
    }

    if (taint) OBJ_TAINT(result);
    return result;
}

/*
 *  call-seq:
 *     array.join(sep=$,)    -> str
 *
 *  Returns a string created by converting each element of the array to
 *  a string, separated by <i>sep</i>.
 *
 *     [ "a", "b", "c" ].join        #=> "abc"
 *     [ "a", "b", "c" ].join("-")   #=> "a-b-c"
 */

static VALUE
rb_ary_join_m(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE sep;

    rb_scan_args(argc, argv, "01", &sep);
    if (NIL_P(sep)) sep = rb_output_fs;

    return rb_ary_join(ary, sep);
}

/*
 *  call-seq:
 *     array.to_s -> string
 *
 *  Returns _self_<code>.join</code>.
 *
 *     [ "a", "e", "i", "o" ].to_s   #=> "aeio"
 *
 */

VALUE
rb_ary_to_s(ary)
    VALUE ary;
{
    if (RARRAY(ary)->len == 0) return rb_str_new(0, 0);

    return rb_ary_join(ary, rb_output_fs);
}

static ID inspect_key;

struct inspect_arg {
    VALUE (*func)();
    VALUE arg1, arg2;
};

static VALUE
inspect_call(arg)
    struct inspect_arg *arg;
{
    return (*arg->func)(arg->arg1, arg->arg2);
}

static VALUE
get_inspect_tbl(create)
    int create;
{
    VALUE inspect_tbl = rb_thread_local_aref(rb_thread_current(), inspect_key);

    if (NIL_P(inspect_tbl)) {
	if (create) {
	  tbl_init:
	    inspect_tbl = rb_ary_new();
	    rb_thread_local_aset(rb_thread_current(), inspect_key, inspect_tbl);
	}
    }
    else if (TYPE(inspect_tbl) != T_ARRAY) {
	rb_warn("invalid inspect_tbl value");
	if (create) goto tbl_init;
	rb_thread_local_aset(rb_thread_current(), inspect_key, Qnil);
	return Qnil;
    }
    return inspect_tbl;
}

static VALUE
inspect_ensure(obj)
    VALUE obj;
{
    VALUE inspect_tbl;

    inspect_tbl = get_inspect_tbl(Qfalse);
    if (!NIL_P(inspect_tbl)) {
	rb_ary_pop(inspect_tbl);
    }
    return 0;
}

VALUE
rb_protect_inspect(func, obj, arg)
    VALUE (*func)(ANYARGS);
    VALUE obj, arg;
{
    struct inspect_arg iarg;
    VALUE inspect_tbl;
    VALUE id;

    inspect_tbl = get_inspect_tbl(Qtrue);
    id = rb_obj_id(obj);
    if (rb_ary_includes(inspect_tbl, id)) {
	return (*func)(obj, arg);
    }
    rb_ary_push(inspect_tbl, id);
    iarg.func = func;
    iarg.arg1 = obj;
    iarg.arg2 = arg;

    return rb_ensure(inspect_call, (VALUE)&iarg, inspect_ensure, obj);
}

VALUE
rb_inspecting_p(obj)
    VALUE obj;
{
    VALUE inspect_tbl;

    inspect_tbl = get_inspect_tbl(Qfalse);
    if (NIL_P(inspect_tbl)) return Qfalse;
    return rb_ary_includes(inspect_tbl, rb_obj_id(obj));
}

static VALUE
inspect_ary(ary)
    VALUE ary;
{
    int tainted = OBJ_TAINTED(ary);
    long i;
    VALUE s, str;

    str = rb_str_buf_new2("[");
    for (i=0; i<RARRAY(ary)->len; i++) {
	s = rb_inspect(RARRAY(ary)->ptr[i]);
	if (OBJ_TAINTED(s)) tainted = Qtrue;
	if (i > 0) rb_str_buf_cat2(str, ", ");
	rb_str_buf_append(str, s);
    }
    rb_str_buf_cat2(str, "]");
    if (tainted) OBJ_TAINT(str);
    return str;
}

/*
 *  call-seq:
 *     array.inspect  -> string
 *
 *  Create a printable version of <i>array</i>.
 */

static VALUE
rb_ary_inspect(ary)
    VALUE ary;
{
    if (RARRAY(ary)->len == 0) return rb_str_new2("[]");
    if (rb_inspecting_p(ary)) return rb_str_new2("[...]");
    return rb_protect_inspect(inspect_ary, ary, 0);
}

/*
 *  call-seq:
 *     array.to_a     -> array
 *
 *  Returns _self_. If called on a subclass of Array, converts
 *  the receiver to an Array object.
 */

static VALUE
rb_ary_to_a(ary)
    VALUE ary;
{
    if (rb_obj_class(ary) != rb_cArray) {
	VALUE dup = rb_ary_new2(RARRAY(ary)->len);
	rb_ary_replace(dup, ary);
	return dup;
    }
    return ary;
}

/*
 *  call-seq:
 *     array.to_ary -> array
 *
 *  Returns _self_.
 */

static VALUE
rb_ary_to_ary_m(ary)
    VALUE ary;
{
    return ary;
}

VALUE
rb_ary_reverse(ary)
    VALUE ary;
{
    VALUE *p1, *p2;
    VALUE tmp;

    rb_ary_modify(ary);
    if (RARRAY(ary)->len > 1) {
	p1 = RARRAY(ary)->ptr;
	p2 = p1 + RARRAY(ary)->len - 1;	/* points last item */

	while (p1 < p2) {
	    tmp = *p1;
	    *p1++ = *p2;
	    *p2-- = tmp;
	}
    }
    return ary;
}

/*
 *  call-seq:
 *     array.reverse!   -> array
 *
 *  Reverses _self_ in place.
 *
 *     a = [ "a", "b", "c" ]
 *     a.reverse!       #=> ["c", "b", "a"]
 *     a                #=> ["c", "b", "a"]
 */

static VALUE
rb_ary_reverse_bang(ary)
    VALUE ary;
{
    return rb_ary_reverse(ary);
}

/*
 *  call-seq:
 *     array.reverse -> an_array
 *
 *  Returns a new array containing <i>self</i>'s elements in reverse order.
 *
 *     [ "a", "b", "c" ].reverse   #=> ["c", "b", "a"]
 *     [ 1 ].reverse               #=> [1]
 */

static VALUE
rb_ary_reverse_m(ary)
    VALUE ary;
{
    return rb_ary_reverse(rb_ary_dup(ary));
}

struct ary_sort_data {
    VALUE ary;
    VALUE *ptr;
    long len;
};

static void
ary_sort_check(data)
    struct ary_sort_data *data;
{
    if (RARRAY(data->ary)->ptr != data->ptr || RARRAY(data->ary)->len != data->len) {
	rb_raise(rb_eArgError, "array modified during sort");
    }
}

static int
sort_1(a, b, data)
    VALUE *a, *b;
    struct ary_sort_data *data;
{
    VALUE retval = rb_yield_values(2, *a, *b);
    int n;

    n = rb_cmpint(retval, *a, *b);
    ary_sort_check(data);
    return n;
}

static int
sort_2(ap, bp, data)
    VALUE *ap, *bp;
    struct ary_sort_data *data;
{
    VALUE retval;
    VALUE a = *ap, b = *bp;
    int n;

    if (FIXNUM_P(a) && FIXNUM_P(b)) {
	if ((long)a > (long)b) return 1;
	if ((long)a < (long)b) return -1;
	return 0;
    }
    if (TYPE(a) == T_STRING) {
	if (TYPE(b) == T_STRING) return rb_str_cmp(a, b);
    }

    retval = rb_funcall(a, id_cmp, 1, b);
    n = rb_cmpint(retval, a, b);
    ary_sort_check(data);

    return n;
}

static VALUE
sort_internal(ary)
    VALUE ary;
{
    struct ary_sort_data data;

    data.ary = ary;
    data.ptr = RARRAY(ary)->ptr; data.len = RARRAY(ary)->len;
    qsort(RARRAY(ary)->ptr, RARRAY(ary)->len, sizeof(VALUE),
	  rb_block_given_p()?sort_1:sort_2, &data);
    return ary;
}

static VALUE
sort_unlock(ary)
    VALUE ary;
{
    FL_UNSET(ary, ARY_TMPLOCK);
    return ary;
}

/*
 *  call-seq:
 *     array.sort!                   -> array
 *     array.sort! {| a,b | block }  -> array
 *
 *  Sorts _self_. Comparisons for
 *  the sort will be done using the <code><=></code> operator or using
 *  an optional code block. The block implements a comparison between
 *  <i>a</i> and <i>b</i>, returning -1, 0, or +1. See also
 *  <code>Enumerable#sort_by</code>.
 *
 *     a = [ "d", "a", "e", "c", "b" ]
 *     a.sort                    #=> ["a", "b", "c", "d", "e"]
 *     a.sort {|x,y| y <=> x }   #=> ["e", "d", "c", "b", "a"]
 */

VALUE
rb_ary_sort_bang(ary)
    VALUE ary;
{
    rb_ary_modify(ary);
    if (RARRAY(ary)->len > 1) {
	FL_SET(ary, ARY_TMPLOCK);	/* prohibit modification during sort */
	rb_ensure(sort_internal, ary, sort_unlock, ary);
    }
    return ary;
}

/*
 *  call-seq:
 *     array.sort                   -> an_array
 *     array.sort {| a,b | block }  -> an_array
 *
 *  Returns a new array created by sorting <i>self</i>. Comparisons for
 *  the sort will be done using the <code><=></code> operator or using
 *  an optional code block. The block implements a comparison between
 *  <i>a</i> and <i>b</i>, returning -1, 0, or +1. See also
 *  <code>Enumerable#sort_by</code>.
 *
 *     a = [ "d", "a", "e", "c", "b" ]
 *     a.sort                    #=> ["a", "b", "c", "d", "e"]
 *     a.sort {|x,y| y <=> x }   #=> ["e", "d", "c", "b", "a"]
 */

VALUE
rb_ary_sort(ary)
    VALUE ary;
{
    ary = rb_ary_dup(ary);
    rb_ary_sort_bang(ary);
    return ary;
}

/*
 *  call-seq:
 *     array.collect {|item| block }  -> an_array
 *     array.map     {|item| block }  -> an_array
 *
 *  Invokes <i>block</i> once for each element of <i>self</i>. Creates a
 *  new array containing the values returned by the block.
 *  See also <code>Enumerable#collect</code>.
 *
 *     a = [ "a", "b", "c", "d" ]
 *     a.collect {|x| x + "!" }   #=> ["a!", "b!", "c!", "d!"]
 *     a                          #=> ["a", "b", "c", "d"]
 */

static VALUE
rb_ary_collect(ary)
    VALUE ary;
{
    long i;
    VALUE collect;

    if (!rb_block_given_p()) {
	return rb_ary_new4(RARRAY(ary)->len, RARRAY(ary)->ptr);
    }

    collect = rb_ary_new2(RARRAY(ary)->len);
    for (i = 0; i < RARRAY(ary)->len; i++) {
	rb_ary_push(collect, rb_yield(RARRAY(ary)->ptr[i]));
    }
    return collect;
}

/*
 *  call-seq:
 *     array.collect! {|item| block }   ->   array
 *     array.map!     {|item| block }   ->   array
 *
 *  Invokes the block once for each element of _self_, replacing the
 *  element with the value returned by _block_.
 *  See also <code>Enumerable#collect</code>.
 *
 *     a = [ "a", "b", "c", "d" ]
 *     a.collect! {|x| x + "!" }
 *     a             #=>  [ "a!", "b!", "c!", "d!" ]
 */

static VALUE
rb_ary_collect_bang(ary)
    VALUE ary;
{
    long i;

    RETURN_ENUMERATOR(ary, 0, 0);
    rb_ary_modify(ary);
    for (i = 0; i < RARRAY(ary)->len; i++) {
	rb_ary_store(ary, i, rb_yield(RARRAY(ary)->ptr[i]));
    }
    return ary;
}

VALUE
rb_values_at(obj, olen, argc, argv, func)
    VALUE obj;
    long olen;
    int argc;
    VALUE *argv;
    VALUE (*func) _((VALUE,long));
{
    VALUE result = rb_ary_new2(argc);
    long beg, len, i, j;

    for (i=0; i<argc; i++) {
	if (FIXNUM_P(argv[i])) {
	    rb_ary_push(result, (*func)(obj, FIX2LONG(argv[i])));
	    continue;
	}
	/* check if idx is Range */
	switch (rb_range_beg_len(argv[i], &beg, &len, olen, 0)) {
	  case Qfalse:
	    break;
	  case Qnil:
	    continue;
	  default:
	    for (j=0; j<len; j++) {
		rb_ary_push(result, (*func)(obj, j+beg));
	    }
	    continue;
	}
	rb_ary_push(result, (*func)(obj, NUM2LONG(argv[i])));
    }
    return result;
}

/*
 *  call-seq:
 *     array.values_at(selector,... )  -> an_array
 *
 *  Returns an array containing the elements in
 *  _self_ corresponding to the given selector(s). The selectors
 *  may be either integer indices or ranges.
 *  See also <code>Array#select</code>.
 *
 *     a = %w{ a b c d e f }
 *     a.values_at(1, 3, 5)
 *     a.values_at(1, 3, 5, 7)
 *     a.values_at(-1, -3, -5, -7)
 *     a.values_at(1..3, 2...5)
 */

static VALUE
rb_ary_values_at(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    return rb_values_at(ary, RARRAY(ary)->len, argc, argv, rb_ary_entry);
}

/*
 *  call-seq:
 *     array.select {|item| block } -> an_array
 *
 *  Invokes the block passing in successive elements from <i>array</i>,
 *  returning an array containing those elements for which the block
 *  returns a true value (equivalent to <code>Enumerable#select</code>).
 *
 *     a = %w{ a b c d e f }
 *     a.select {|v| v =~ /[aeiou]/}   #=> ["a", "e"]
 */

static VALUE
rb_ary_select(ary)
    VALUE ary;
{
    VALUE result;
    long i;

    RETURN_ENUMERATOR(ary, 0, 0);
    result = rb_ary_new2(RARRAY(ary)->len);
    for (i = 0; i < RARRAY(ary)->len; i++) {
	if (RTEST(rb_yield(RARRAY(ary)->ptr[i]))) {
	    rb_ary_push(result, rb_ary_elt(ary, i));
	}
    }
    return result;
}

/*
 *  call-seq:
 *     array.delete(obj)            -> obj or nil
 *     array.delete(obj) { block }  -> obj or nil
 *
 *  Deletes items from <i>self</i> that are equal to <i>obj</i>. If
 *  the item is not found, returns <code>nil</code>. If the optional
 *  code block is given, returns the result of <i>block</i> if the item
 *  is not found.
 *
 *     a = [ "a", "b", "b", "b", "c" ]
 *     a.delete("b")                   #=> "b"
 *     a                               #=> ["a", "c"]
 *     a.delete("z")                   #=> nil
 *     a.delete("z") { "not found" }   #=> "not found"
 */

VALUE
rb_ary_delete(ary, item)
    VALUE ary;
    VALUE item;
{
    long i1, i2;

    for (i1 = i2 = 0; i1 < RARRAY(ary)->len; i1++) {
	VALUE e = RARRAY(ary)->ptr[i1];

	if (rb_equal(e, item)) continue;
	if (i1 != i2) {
	    rb_ary_store(ary, i2, e);
	}
	i2++;
    }
    if (RARRAY(ary)->len == i2) {
	if (rb_block_given_p()) {
	    return rb_yield(item);
	}
	return Qnil;
    }

    rb_ary_modify(ary);
    if (RARRAY(ary)->len > i2) {
	RARRAY(ary)->len = i2;
	if (i2 * 2 < RARRAY(ary)->aux.capa &&
	    RARRAY(ary)->aux.capa > ARY_DEFAULT_SIZE) {
	    REALLOC_N(RARRAY(ary)->ptr, VALUE, i2 * 2);
	    RARRAY(ary)->aux.capa = i2 * 2;
	}
    }

    return item;
}

VALUE
rb_ary_delete_at(ary, pos)
    VALUE ary;
    long pos;
{
    long i, len = RARRAY(ary)->len;
    VALUE del;

    if (pos >= len) return Qnil;
    if (pos < 0) {
	pos += len;
	if (pos < 0) return Qnil;
    }

    rb_ary_modify(ary);
    del = RARRAY(ary)->ptr[pos];
    for (i = pos + 1; i < len; i++, pos++) {
	RARRAY(ary)->ptr[pos] = RARRAY(ary)->ptr[i];
    }
    RARRAY(ary)->len = pos;

    return del;
}

/*
 *  call-seq:
 *     array.delete_at(index)  -> obj or nil
 *
 *  Deletes the element at the specified index, returning that element,
 *  or <code>nil</code> if the index is out of range. See also
 *  <code>Array#slice!</code>.
 *
 *     a = %w( ant bat cat dog )
 *     a.delete_at(2)    #=> "cat"
 *     a                 #=> ["ant", "bat", "dog"]
 *     a.delete_at(99)   #=> nil
 */

static VALUE
rb_ary_delete_at_m(ary, pos)
    VALUE ary, pos;
{
    return rb_ary_delete_at(ary, NUM2LONG(pos));
}

/*
 *  call-seq:
 *     array.slice!(index)         -> obj or nil
 *     array.slice!(start, length) -> sub_array or nil
 *     array.slice!(range)         -> sub_array or nil
 *
 *  Deletes the element(s) given by an index (optionally with a length)
 *  or by a range. Returns the deleted object, subarray, or
 *  <code>nil</code> if the index is out of range. Equivalent to:
 *
 *     def slice!(*args)
 *       result = self[*args]
 *       self[*args] = nil
 *       result
 *     end
 *
 *     a = [ "a", "b", "c" ]
 *     a.slice!(1)     #=> "b"
 *     a               #=> ["a", "c"]
 *     a.slice!(-1)    #=> "c"
 *     a               #=> ["a"]
 *     a.slice!(100)   #=> nil
 *     a               #=> ["a"]
 */

static VALUE
rb_ary_slice_bang(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE arg1, arg2;
    long pos, len, orig_len;

    rb_ary_modify_check(ary);
    if (rb_scan_args(argc, argv, "11", &arg1, &arg2) == 2) {
	pos = NUM2LONG(arg1);
	len = NUM2LONG(arg2);
      delete_pos_len:
	if (len < 0) return Qnil;
	orig_len = RARRAY_LEN(ary);
	if (pos < 0) {
	    pos += orig_len;
	    if (pos < 0) return Qnil;
	}
	else if (orig_len < pos) return Qnil;
	if (orig_len < pos + len) {
	    len = orig_len - pos;
	}
	if (len == 0) return rb_ary_new2(0);
	arg2 = rb_ary_new4(len, RARRAY_PTR(ary)+pos);
	RBASIC(arg2)->klass = rb_obj_class(ary);
	rb_ary_splice(ary, pos, len, Qnil);	/* Qundef in 1.9 */
	return arg2;
    }

    if (!FIXNUM_P(arg1)) {
	switch (rb_range_beg_len(arg1, &pos, &len, RARRAY_LEN(ary), 0)) {
	  case Qtrue:
	    /* valid range */
	    goto delete_pos_len;
	  case Qnil:
	    /* invalid range */
	    return Qnil;
	  default:
	    /* not a range */
	    break;
	}
    }

    return rb_ary_delete_at(ary, NUM2LONG(arg1));
}

/*
 *  call-seq:
 *     array.reject! {|item| block }  -> array or nil
 *
 *  Equivalent to <code>Array#delete_if</code>, deleting elements from
 *  _self_ for which the block evaluates to true, but returns
 *  <code>nil</code> if no changes were made. Also see
 *  <code>Enumerable#reject</code>.
 */

static VALUE
rb_ary_reject_bang(ary)
    VALUE ary;
{
    long i1, i2;

    RETURN_ENUMERATOR(ary, 0, 0);
    rb_ary_modify(ary);
    for (i1 = i2 = 0; i1 < RARRAY(ary)->len; i1++) {
	VALUE v = RARRAY(ary)->ptr[i1];
	if (RTEST(rb_yield(v))) continue;
	if (i1 != i2) {
	    rb_ary_store(ary, i2, v);
	}
	i2++;
    }
    if (RARRAY(ary)->len == i2) return Qnil;
    if (i2 < RARRAY(ary)->len)
	RARRAY(ary)->len = i2;

    return ary;
}

/*
 *  call-seq:
 *     array.reject {|item| block }  -> an_array
 *
 *  Returns a new array containing the items in _self_
 *  for which the block is not true.
 */

static VALUE
rb_ary_reject(ary)
    VALUE ary;
{
    RETURN_ENUMERATOR(ary, 0, 0);
    ary = rb_ary_dup(ary);
    rb_ary_reject_bang(ary);
    return ary;
}

/*
 *  call-seq:
 *     array.delete_if {|item| block }  -> array
 *
 *  Deletes every element of <i>self</i> for which <i>block</i> evaluates
 *  to <code>true</code>.
 *
 *     a = [ "a", "b", "c" ]
 *     a.delete_if {|x| x >= "b" }   #=> ["a"]
 */

static VALUE
rb_ary_delete_if(ary)
    VALUE ary;
{
    RETURN_ENUMERATOR(ary, 0, 0);
    rb_ary_reject_bang(ary);
    return ary;
}

/*
 *  call-seq:
 *     array.zip(arg, ...)                   -> an_array
 *     array.zip(arg, ...) {| arr | block }  -> nil
 *
 *  Converts any arguments to arrays, then merges elements of
 *  <i>self</i> with corresponding elements from each argument. This
 *  generates a sequence of <code>self.size</code> <em>n</em>-element
 *  arrays, where <em>n</em> is one more that the count of arguments. If
 *  the size of any argument is less than <code>enumObj.size</code>,
 *  <code>nil</code> values are supplied. If a block given, it is
 *  invoked for each output array, otherwise an array of arrays is
 *  returned.
 *
 *     a = [ 4, 5, 6 ]
 *     b = [ 7, 8, 9 ]
 *
 *     [1,2,3].zip(a, b)      #=> [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
 *     [1,2].zip(a,b)         #=> [[1, 4, 7], [2, 5, 8]]
 *     a.zip([1,2],[8])       #=> [[4,1,8], [5,2,nil], [6,nil,nil]]
 */

static VALUE
rb_ary_zip(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    int i, j;
    long len;
    VALUE result;

    for (i=0; i<argc; i++) {
	argv[i] = to_ary(argv[i]);
    }
    if (rb_block_given_p()) {
	for (i=0; i<RARRAY(ary)->len; i++) {
	    VALUE tmp = rb_ary_new2(argc+1);

	    rb_ary_push(tmp, rb_ary_elt(ary, i));
	    for (j=0; j<argc; j++) {
		rb_ary_push(tmp, rb_ary_elt(argv[j], i));
	    }
	    rb_yield(tmp);
	}
	return Qnil;
    }
    len = RARRAY(ary)->len;
    result = rb_ary_new2(len);
    for (i=0; i<len; i++) {
	VALUE tmp = rb_ary_new2(argc+1);

	rb_ary_push(tmp, rb_ary_elt(ary, i));
	for (j=0; j<argc; j++) {
	    rb_ary_push(tmp, rb_ary_elt(argv[j], i));
	}
	rb_ary_push(result, tmp);
    }
    return result;
}

/*
 *  call-seq:
 *     array.transpose -> an_array
 *
 *  Assumes that <i>self</i> is an array of arrays and transposes the
 *  rows and columns.
 *
 *     a = [[1,2], [3,4], [5,6]]
 *     a.transpose   #=> [[1, 3, 5], [2, 4, 6]]
 */

static VALUE
rb_ary_transpose(ary)
    VALUE ary;
{
    long elen = -1, alen, i, j;
    VALUE tmp, result = 0;

    alen = RARRAY(ary)->len;
    if (alen == 0) return rb_ary_dup(ary);
    for (i=0; i<alen; i++) {
	tmp = to_ary(rb_ary_elt(ary, i));
	if (elen < 0) {		/* first element */
	    elen = RARRAY(tmp)->len;
	    result = rb_ary_new2(elen);
	    for (j=0; j<elen; j++) {
		rb_ary_store(result, j, rb_ary_new2(alen));
	    }
	}
	else if (elen != RARRAY(tmp)->len) {
	    rb_raise(rb_eIndexError, "element size differs (%d should be %d)",
		     RARRAY(tmp)->len, elen);
	}
	for (j=0; j<elen; j++) {
	    rb_ary_store(rb_ary_elt(result, j), i, rb_ary_elt(tmp, j));
	}
    }
    return result;
}

/*
 *  call-seq:
 *     array.replace(other_array)  -> array
 *
 *  Replaces the contents of <i>self</i> with the contents of
 *  <i>other_array</i>, truncating or expanding if necessary.
 *
 *     a = [ "a", "b", "c", "d", "e" ]
 *     a.replace([ "x", "y", "z" ])   #=> ["x", "y", "z"]
 *     a                              #=> ["x", "y", "z"]
 */

static VALUE
rb_ary_replace(copy, orig)
    VALUE copy, orig;
{
    VALUE shared;

    rb_ary_modify(copy);
    orig = to_ary(orig);
    if (copy == orig) return copy;
    shared = ary_make_shared(orig);
    if (RARRAY(copy)->ptr && !FL_TEST(copy, ELTS_SHARED))
	free(RARRAY(copy)->ptr);
    RARRAY(copy)->ptr = RARRAY(orig)->ptr;
    RARRAY(copy)->len = RARRAY(orig)->len;
    RARRAY(copy)->aux.shared = shared;
    FL_SET(copy, ELTS_SHARED);

    return copy;
}

/*
 *  call-seq:
 *     array.clear    ->  array
 *
 *  Removes all elements from _self_.
 *
 *     a = [ "a", "b", "c", "d", "e" ]
 *     a.clear    #=> [ ]
 */

VALUE
rb_ary_clear(ary)
    VALUE ary;
{
    rb_ary_modify(ary);
    RARRAY(ary)->len = 0;
    if (ARY_DEFAULT_SIZE * 2 < RARRAY(ary)->aux.capa) {
	REALLOC_N(RARRAY(ary)->ptr, VALUE, ARY_DEFAULT_SIZE * 2);
	RARRAY(ary)->aux.capa = ARY_DEFAULT_SIZE * 2;
    }
    return ary;
}

/*
 *  call-seq:
 *     array.fill(obj)                                -> array
 *     array.fill(obj, start [, length])              -> array
 *     array.fill(obj, range )                        -> array
 *     array.fill {|index| block }                    -> array
 *     array.fill(start [, length] ) {|index| block } -> array
 *     array.fill(range) {|index| block }             -> array
 *
 *  The first three forms set the selected elements of <i>self</i> (which
 *  may be the entire array) to <i>obj</i>. A <i>start</i> of
 *  <code>nil</code> is equivalent to zero. A <i>length</i> of
 *  <code>nil</code> is equivalent to <i>self.length</i>. The last three
 *  forms fill the array with the value of the block. The block is
 *  passed the absolute index of each element to be filled.
 *
 *     a = [ "a", "b", "c", "d" ]
 *     a.fill("x")              #=> ["x", "x", "x", "x"]
 *     a.fill("z", 2, 2)        #=> ["x", "x", "z", "z"]
 *     a.fill("y", 0..1)        #=> ["y", "y", "z", "z"]
 *     a.fill {|i| i*i}         #=> [0, 1, 4, 9]
 *     a.fill(-2) {|i| i*i*i}   #=> [0, 1, 8, 27]
 */

static VALUE
rb_ary_fill(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE item, arg1, arg2;
    long beg = 0, end = 0, len = 0;
    VALUE *p, *pend;
    int block_p = Qfalse;

    if (rb_block_given_p()) {
	block_p = Qtrue;
	rb_scan_args(argc, argv, "02", &arg1, &arg2);
	argc += 1;		/* hackish */
    }
    else {
	rb_scan_args(argc, argv, "12", &item, &arg1, &arg2);
    }
    switch (argc) {
      case 1:
	beg = 0;
	len = RARRAY(ary)->len;
	break;
      case 2:
	if (rb_range_beg_len(arg1, &beg, &len, RARRAY(ary)->len, 1)) {
	    break;
	}
	/* fall through */
      case 3:
	beg = NIL_P(arg1) ? 0 : NUM2LONG(arg1);
	if (beg < 0) {
	    beg = RARRAY(ary)->len + beg;
	    if (beg < 0) beg = 0;
	}
	len = NIL_P(arg2) ? RARRAY(ary)->len - beg : NUM2LONG(arg2);
	break;
    }
    rb_ary_modify(ary);
    if (len < 0) {
        return ary;
    }
    if (beg >= ARY_MAX_SIZE || len > ARY_MAX_SIZE - beg) {
	rb_raise(rb_eArgError, "argument too big");
    }
    end = beg + len;
    if (end > RARRAY(ary)->len) {
	if (end >= RARRAY(ary)->aux.capa) {
	    REALLOC_N(RARRAY(ary)->ptr, VALUE, end);
	    RARRAY(ary)->aux.capa = end;
	}
	rb_mem_clear(RARRAY(ary)->ptr + RARRAY(ary)->len, end - RARRAY(ary)->len);
	RARRAY(ary)->len = end;
    }

    if (block_p) {
	VALUE v;
	long i;

	for (i=beg; i<end; i++) {
	    v = rb_yield(LONG2NUM(i));
	    if (i>=RARRAY(ary)->len) break;
	    RARRAY(ary)->ptr[i] = v;
	}
    }
    else {
	p = RARRAY(ary)->ptr + beg;
	pend = p + len;
	while (p < pend) {
	    *p++ = item;
	}
    }
    return ary;
}

/*
 *  call-seq:
 *     array + other_array   -> an_array
 *
 *  Concatenation---Returns a new array built by concatenating the
 *  two arrays together to produce a third array.
 *
 *     [ 1, 2, 3 ] + [ 4, 5 ]    #=> [ 1, 2, 3, 4, 5 ]
 */

VALUE
rb_ary_plus(x, y)
    VALUE x, y;
{
    VALUE z;
    long len;

    y = to_ary(y);
    len = RARRAY(x)->len + RARRAY(y)->len;
    z = rb_ary_new2(len);
    MEMCPY(RARRAY(z)->ptr, RARRAY(x)->ptr, VALUE, RARRAY(x)->len);
    MEMCPY(RARRAY(z)->ptr + RARRAY(x)->len, RARRAY(y)->ptr, VALUE, RARRAY(y)->len);
    RARRAY(z)->len = len;
    return z;
}

/*
 *  call-seq:
 *     array.concat(other_array)   ->  array
 *
 *  Appends the elements in other_array to _self_.
 *
 *     [ "a", "b" ].concat( ["c", "d"] ) #=> [ "a", "b", "c", "d" ]
 */


VALUE
rb_ary_concat(x, y)
    VALUE x, y;
{
    y = to_ary(y);
    if (RARRAY(y)->len > 0) {
	rb_ary_splice(x, RARRAY(x)->len, 0, y);
    }
    return x;
}


/*
 *  call-seq:
 *     array * int     ->    an_array
 *     array * str     ->    a_string
 *
 *  Repetition---With a String argument, equivalent to
 *  self.join(str). Otherwise, returns a new array
 *  built by concatenating the _int_ copies of _self_.
 *
 *
 *     [ 1, 2, 3 ] * 3    #=> [ 1, 2, 3, 1, 2, 3, 1, 2, 3 ]
 *     [ 1, 2, 3 ] * ","  #=> "1,2,3"
 *
 */

static VALUE
rb_ary_times(ary, times)
    VALUE ary, times;
{
    VALUE ary2, tmp;
    long i, len;

    tmp = rb_check_string_type(times);
    if (!NIL_P(tmp)) {
	return rb_ary_join(ary, tmp);
    }

    len = NUM2LONG(times);
    if (len == 0) return ary_new(rb_obj_class(ary), 0);
    if (len < 0) {
	rb_raise(rb_eArgError, "negative argument");
    }
    if (ARY_MAX_SIZE/len < RARRAY(ary)->len) {
	rb_raise(rb_eArgError, "argument too big");
    }
    len *= RARRAY(ary)->len;

    ary2 = ary_new(rb_obj_class(ary), len);
    RARRAY(ary2)->len = len;

    for (i=0; i<len; i+=RARRAY(ary)->len) {
	MEMCPY(RARRAY(ary2)->ptr+i, RARRAY(ary)->ptr, VALUE, RARRAY(ary)->len);
    }
    OBJ_INFECT(ary2, ary);

    return ary2;
}

/*
 *  call-seq:
 *     array.assoc(obj)   ->  an_array  or  nil
 *
 *  Searches through an array whose elements are also arrays
 *  comparing _obj_ with the first element of each contained array
 *  using obj.==.
 *  Returns the first contained array that matches (that
 *  is, the first associated array),
 *  or +nil+ if no match is found.
 *  See also <code>Array#rassoc</code>.
 *
 *     s1 = [ "colors", "red", "blue", "green" ]
 *     s2 = [ "letters", "a", "b", "c" ]
 *     s3 = "foo"
 *     a  = [ s1, s2, s3 ]
 *     a.assoc("letters")  #=> [ "letters", "a", "b", "c" ]
 *     a.assoc("foo")      #=> nil
 */

VALUE
rb_ary_assoc(ary, key)
    VALUE ary, key;
{
    long i;
    VALUE v;

    for (i = 0; i < RARRAY(ary)->len; ++i) {
	v = rb_check_array_type(RARRAY(ary)->ptr[i]);
	if (!NIL_P(v) && RARRAY(v)->len > 0 &&
	    rb_equal(RARRAY(v)->ptr[0], key))
	    return v;
    }
    return Qnil;
}

/*
 *  call-seq:
 *     array.rassoc(key) -> an_array or nil
 *
 *  Searches through the array whose elements are also arrays. Compares
 *  <em>key</em> with the second element of each contained array using
 *  <code>==</code>. Returns the first contained array that matches. See
 *  also <code>Array#assoc</code>.
 *
 *     a = [ [ 1, "one"], [2, "two"], [3, "three"], ["ii", "two"] ]
 *     a.rassoc("two")    #=> [2, "two"]
 *     a.rassoc("four")   #=> nil
 */

VALUE
rb_ary_rassoc(ary, value)
    VALUE ary, value;
{
    long i;
    VALUE v;

    for (i = 0; i < RARRAY(ary)->len; ++i) {
	v = RARRAY(ary)->ptr[i];
	if (TYPE(v) == T_ARRAY &&
	    RARRAY(v)->len > 1 &&
	    rb_equal(RARRAY(v)->ptr[1], value))
	    return v;
    }
    return Qnil;
}

static VALUE recursive_equal _((VALUE, VALUE, int));
static VALUE
recursive_equal(ary1, ary2, recur)
    VALUE ary1, ary2;
    int recur;
{
    long i;

    if (recur) return Qfalse;
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (!rb_equal(rb_ary_elt(ary1, i), rb_ary_elt(ary2, i)))
	    return Qfalse;
    }
    return Qtrue;
}

/*
 *  call-seq:
 *     array == other_array   ->   bool
 *
 *  Equality---Two arrays are equal if they contain the same number
 *  of elements and if each element is equal to (according to
 *  Object.==) the corresponding element in the other array.
 *
 *     [ "a", "c" ]    == [ "a", "c", 7 ]     #=> false
 *     [ "a", "c", 7 ] == [ "a", "c", 7 ]     #=> true
 *     [ "a", "c", 7 ] == [ "a", "d", "f" ]   #=> false
 *
 */

static VALUE
rb_ary_equal(ary1, ary2)
    VALUE ary1, ary2;
{
    if (ary1 == ary2) return Qtrue;
    if (TYPE(ary2) != T_ARRAY) {
	if (!rb_respond_to(ary2, rb_intern("to_ary"))) {
	    return Qfalse;
	}
	return rb_equal(ary2, ary1);
    }
    if (RARRAY(ary1)->len != RARRAY(ary2)->len) return Qfalse;
    return rb_exec_recursive(recursive_equal, ary1, ary2);
}

static VALUE recursive_eql _((VALUE, VALUE, int));
static VALUE
recursive_eql(ary1, ary2, recur)
    VALUE ary1, ary2;
    int recur;
{
    long i;

    if (recur) return Qfalse;
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (!rb_eql(rb_ary_elt(ary1, i), rb_ary_elt(ary2, i)))
	    return Qfalse;
    }
    return Qtrue;
}

/*
 *  call-seq:
 *     array.eql?(other)  -> true or false
 *
 *  Returns <code>true</code> if _array_ and _other_ are the same object,
 *  or are both arrays with the same content.
 */

static VALUE
rb_ary_eql(ary1, ary2)
    VALUE ary1, ary2;
{
    if (ary1 == ary2) return Qtrue;
    if (TYPE(ary2) != T_ARRAY) return Qfalse;
    if (RARRAY(ary1)->len != RARRAY(ary2)->len) return Qfalse;
    return rb_exec_recursive(recursive_eql, ary1, ary2);
}

static VALUE recursive_hash _((VALUE, VALUE, int));
static VALUE
recursive_hash(ary, dummy, recur)
    VALUE ary;
    VALUE dummy;
    int recur;
{
    long i, h;
    VALUE n;

    if (recur) {
	return LONG2FIX(0);
    }

    h = RARRAY(ary)->len;
    for (i=0; i<RARRAY(ary)->len; i++) {
	h = (h << 1) | (h<0 ? 1 : 0);
	n = rb_hash(RARRAY(ary)->ptr[i]);
	h ^= NUM2LONG(n);
    }
    return LONG2FIX(h);
}

/*
 *  call-seq:
 *     array.hash   -> fixnum
 *
 *  Compute a hash-code for this array. Two arrays with the same content
 *  will have the same hash code (and will compare using <code>eql?</code>).
 */

static VALUE
rb_ary_hash(ary)
    VALUE ary;
{
    return rb_exec_recursive(recursive_hash, ary, 0);
}

/*
 *  call-seq:
 *     array.include?(obj)   -> true or false
 *
 *  Returns <code>true</code> if the given object is present in
 *  <i>self</i> (that is, if any object <code>==</code> <i>anObject</i>),
 *  <code>false</code> otherwise.
 *
 *     a = [ "a", "b", "c" ]
 *     a.include?("b")   #=> true
 *     a.include?("z")   #=> false
 */

VALUE
rb_ary_includes(ary, item)
    VALUE ary;
    VALUE item;
{
    long i;

    for (i=0; i<RARRAY(ary)->len; i++) {
	if (rb_equal(RARRAY(ary)->ptr[i], item)) {
	    return Qtrue;
	}
    }
    return Qfalse;
}


static VALUE recursive_cmp _((VALUE, VALUE, int));
static VALUE
recursive_cmp(ary1, ary2, recur)
    VALUE ary1;
    VALUE ary2;
    int recur;
{
    long i, len;

    if (recur) return Qnil;
    len = RARRAY(ary1)->len;
    if (len > RARRAY(ary2)->len) {
	len = RARRAY(ary2)->len;
    }
    for (i=0; i<len; i++) {
	VALUE v = rb_funcall(rb_ary_elt(ary1, i), id_cmp, 1, rb_ary_elt(ary2, i));
	if (v != INT2FIX(0)) {
	    return v;
	}
    }
    return Qundef;
}

/*
 *  call-seq:
 *     array <=> other_array   ->  -1, 0, +1 or nil
 *
 *  Comparison---Returns an integer (-1, 0,
 *  or +1) if this array is less than, equal to, or greater than
 *  other_array.  Each object in each array is compared
 *  (using <=>). If any value isn't
 *  equal, then that inequality is the return value. If all the
 *  values found are equal, then the return is based on a
 *  comparison of the array lengths.  Thus, two arrays are
 *  ``equal'' according to <code>Array#<=></code> if and only if they have
 *  the same length and the value of each element is equal to the
 *  value of the corresponding element in the other array.
 *
 *     [ "a", "a", "c" ]    <=> [ "a", "b", "c" ]   #=> -1
 *     [ 1, 2, 3, 4, 5, 6 ] <=> [ 1, 2 ]            #=> +1
 *
 */

VALUE
rb_ary_cmp(ary1, ary2)
    VALUE ary1, ary2;
{
    long len;
    VALUE v;

    ary2 = to_ary(ary2);
    if (ary1 == ary2) return INT2FIX(0);
    v = rb_exec_recursive(recursive_cmp, ary1, ary2);
    if (v != Qundef) return v;
    len = RARRAY(ary1)->len - RARRAY(ary2)->len;
    if (len == 0) return INT2FIX(0);
    if (len > 0) return INT2FIX(1);
    return INT2FIX(-1);
}

static VALUE
ary_make_hash(ary1, ary2)
    VALUE ary1, ary2;
{
    VALUE hash = rb_hash_new();
    long i;

    for (i=0; i<RARRAY(ary1)->len; i++) {
	rb_hash_aset(hash, RARRAY(ary1)->ptr[i], Qtrue);
    }
    if (ary2) {
	for (i=0; i<RARRAY(ary2)->len; i++) {
	    rb_hash_aset(hash, RARRAY(ary2)->ptr[i], Qtrue);
	}
    }
    return hash;
}

/*
 *  call-seq:
 *     array - other_array    -> an_array
 *
 *  Array Difference---Returns a new array that is a copy of
 *  the original array, removing any items that also appear in
 *  other_array. (If you need set-like behavior, see the
 *  library class Set.)
 *
 *     [ 1, 1, 2, 2, 3, 3, 4, 5 ] - [ 1, 2, 4 ]  #=>  [ 3, 3, 5 ]
 */

static VALUE
rb_ary_diff(ary1, ary2)
    VALUE ary1, ary2;
{
    VALUE ary3;
    volatile VALUE hash;
    long i;

    hash = ary_make_hash(to_ary(ary2), 0);
    ary3 = rb_ary_new();

    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (st_lookup(RHASH(hash)->tbl, RARRAY(ary1)->ptr[i], 0)) continue;
	rb_ary_push(ary3, rb_ary_elt(ary1, i));
    }
    return ary3;
}

/*
 *  call-seq:
 *     array & other_array
 *
 *  Set Intersection---Returns a new array
 *  containing elements common to the two arrays, with no duplicates.
 *
 *     [ 1, 1, 3, 5 ] & [ 1, 2, 3 ]   #=> [ 1, 3 ]
 */


static VALUE
rb_ary_and(ary1, ary2)
    VALUE ary1, ary2;
{
    VALUE hash, ary3, v, vv;
    long i;

    ary2 = to_ary(ary2);
    ary3 = rb_ary_new2(RARRAY(ary1)->len < RARRAY(ary2)->len ?
	    RARRAY(ary1)->len : RARRAY(ary2)->len);
    hash = ary_make_hash(ary2, 0);

    for (i=0; i<RARRAY(ary1)->len; i++) {
	v = vv = rb_ary_elt(ary1, i);
	if (st_delete(RHASH(hash)->tbl, (st_data_t*)&vv, 0)) {
	    rb_ary_push(ary3, v);
	}
    }

    return ary3;
}

/*
 *  call-seq:
 *     array | other_array     ->  an_array
 *
 *  Set Union---Returns a new array by joining this array with
 *  other_array, removing duplicates.
 *
 *     [ "a", "b", "c" ] | [ "c", "d", "a" ]
 *            #=> [ "a", "b", "c", "d" ]
 */

static VALUE
rb_ary_or(ary1, ary2)
    VALUE ary1, ary2;
{
    VALUE hash, ary3;
    VALUE v, vv;
    long i;

    ary2 = to_ary(ary2);
    ary3 = rb_ary_new2(RARRAY(ary1)->len+RARRAY(ary2)->len);
    hash = ary_make_hash(ary1, ary2);

    for (i=0; i<RARRAY(ary1)->len; i++) {
	v = vv = rb_ary_elt(ary1, i);
	if (st_delete(RHASH(hash)->tbl, (st_data_t*)&vv, 0)) {
	    rb_ary_push(ary3, v);
	}
    }
    for (i=0; i<RARRAY(ary2)->len; i++) {
	v = vv = rb_ary_elt(ary2, i);
	if (st_delete(RHASH(hash)->tbl, (st_data_t*)&vv, 0)) {
	    rb_ary_push(ary3, v);
	}
    }
    return ary3;
}

/*
 *  call-seq:
 *     array.uniq! -> array or nil
 *
 *  Removes duplicate elements from _self_.
 *  Returns <code>nil</code> if no changes are made (that is, no
 *  duplicates are found).
 *
 *     a = [ "a", "a", "b", "b", "c" ]
 *     a.uniq!   #=> ["a", "b", "c"]
 *     b = [ "a", "b", "c" ]
 *     b.uniq!   #=> nil
 */

static VALUE
rb_ary_uniq_bang(ary)
    VALUE ary;
{
    VALUE hash, v, vv;
    long i, j;

    hash = ary_make_hash(ary, 0);

    if (RARRAY(ary)->len == RHASH(hash)->tbl->num_entries) {
	return Qnil;
    }
    for (i=j=0; i<RARRAY(ary)->len; i++) {
	v = vv = rb_ary_elt(ary, i);
	if (st_delete(RHASH(hash)->tbl, (st_data_t*)&vv, 0)) {
	    rb_ary_store(ary, j++, v);
	}
    }
    RARRAY(ary)->len = j;

    return ary;
}

/*
 *  call-seq:
 *     array.uniq   -> an_array
 *
 *  Returns a new array by removing duplicate values in <i>self</i>.
 *
 *     a = [ "a", "a", "b", "b", "c" ]
 *     a.uniq   #=> ["a", "b", "c"]
 */

static VALUE
rb_ary_uniq(ary)
    VALUE ary;
{
    ary = rb_ary_dup(ary);
    rb_ary_uniq_bang(ary);
    return ary;
}

/*
 *  call-seq:
 *     array.compact!    ->   array  or  nil
 *
 *  Removes +nil+ elements from array.
 *  Returns +nil+ if no changes were made.
 *
 *     [ "a", nil, "b", nil, "c" ].compact! #=> [ "a", "b", "c" ]
 *     [ "a", "b", "c" ].compact!           #=> nil
 */

static VALUE
rb_ary_compact_bang(ary)
    VALUE ary;
{
    VALUE *p, *t, *end;

    rb_ary_modify(ary);
    p = t = RARRAY(ary)->ptr;
    end = p + RARRAY(ary)->len;

    while (t < end) {
	if (NIL_P(*t)) t++;
	else *p++ = *t++;
    }
    if (RARRAY(ary)->len == (p - RARRAY(ary)->ptr)) {
	return Qnil;
    }
    RARRAY(ary)->len = RARRAY(ary)->aux.capa = (p - RARRAY(ary)->ptr);
    REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->len);

    return ary;
}

/*
 *  call-seq:
 *     array.compact     ->  an_array
 *
 *  Returns a copy of _self_ with all +nil+ elements removed.
 *
 *     [ "a", nil, "b", nil, "c", nil ].compact
 *                       #=> [ "a", "b", "c" ]
 */

static VALUE
rb_ary_compact(ary)
    VALUE ary;
{
    ary = rb_ary_dup(ary);
    rb_ary_compact_bang(ary);
    return ary;
}

/*
 *  call-seq:
 *     array.nitems -> int
 *
 *  Returns the number of non-<code>nil</code> elements in _self_.
 *
 *  May be zero.
 *
 *     [ 1, nil, 3, nil, 5 ].nitems   #=> 3
 */

static VALUE
rb_ary_nitems(ary)
    VALUE ary;
{
    long n = 0;
    VALUE *p, *pend;

    rb_warn("Array#nitems is deprecated; use Array#count { |i| !i.nil? }");

    for (p = RARRAY(ary)->ptr, pend = p + RARRAY(ary)->len; p < pend; p++) {
	if (!NIL_P(*p)) n++;
    }
    return LONG2NUM(n);
}

/*
 *  call-seq:
 *     array.count      -> int
 *     array.count(obj) -> int
 *     array.count { |item| block }  -> int
 *
 *  Returns the number of elements.  If an argument is given, counts
 *  the number of elements which equals to <i>obj</i>.  If a block is
 *  given, counts the number of elements yielding a true value.
 *
 *     ary = [1, 2, 4, 2]
 *     ary.count             # => 4
 *     ary.count(2)          # => 2
 *     ary.count{|x|x%2==0}  # => 3
 *
 */

static VALUE
rb_ary_count(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    long n = 0;

    if (argc == 0) {
	VALUE *p, *pend;

	if (!rb_block_given_p())
	    return LONG2NUM(RARRAY_LEN(ary));

	for (p = RARRAY_PTR(ary), pend = p + RARRAY_LEN(ary); p < pend; p++) {
	    if (RTEST(rb_yield(*p))) n++;
	}
    }
    else {
	VALUE obj, *p, *pend;

	rb_scan_args(argc, argv, "1", &obj);
	if (rb_block_given_p()) {
	    rb_warn("given block not used");
	}
	for (p = RARRAY_PTR(ary), pend = p + RARRAY_LEN(ary); p < pend; p++) {
	    if (rb_equal(*p, obj)) n++;
	}
    }

    return LONG2NUM(n);
}

static VALUE
flatten(ary, level, modified)
    VALUE ary;
    int level;
    int *modified;
{
    long i = 0;
    VALUE stack, result, tmp, elt;
    st_table *memo;
    st_data_t id;

    stack = ary_new(0, ARY_DEFAULT_SIZE);
    result = ary_new(0, RARRAY_LEN(ary));
    memo = st_init_numtable();
    st_insert(memo, (st_data_t)ary, (st_data_t)Qtrue);
    *modified = 0;

    while (1) {
	while (i < RARRAY(ary)->len) {
	    elt = RARRAY(ary)->ptr[i++];
	    tmp = rb_check_array_type(elt);
	    if (RBASIC(result)->klass) {
		rb_raise(rb_eRuntimeError, "flatten reentered");
	    }
	    if (NIL_P(tmp) || (level >= 0 && RARRAY(stack)->len / 2 >= level)) {
		rb_ary_push(result, elt);
	    }
	    else {
		*modified = 1;
		id = (st_data_t)tmp;
		if (st_lookup(memo, id, 0)) {
		    st_free_table(memo);
		    rb_raise(rb_eArgError, "tried to flatten recursive array");
		}
		st_insert(memo, id, (st_data_t)Qtrue);
		rb_ary_push(stack, ary);
		rb_ary_push(stack, LONG2NUM(i));
		ary = tmp;
		i = 0;
	    }
	}
	if (RARRAY(stack)->len == 0) {
	    break;
	}
	id = (st_data_t)ary;
	st_delete(memo, &id, 0);
	tmp = rb_ary_pop(stack);
	i = NUM2LONG(tmp);
	ary = rb_ary_pop(stack);
    }

    st_free_table(memo);

    RBASIC(result)->klass = rb_class_of(ary);
    return result;
}

/*
 *  call-seq:
 *     array.flatten! -> array or nil
 *     array.flatten!(level) -> array or nil
 *
 *  Flattens _self_ in place.
 *  Returns <code>nil</code> if no modifications were made (i.e.,
 *  <i>array</i> contains no subarrays.)  If the optional <i>level</i>
 *  argument determines the level of recursion to flatten.
 *
 *     a = [ 1, 2, [3, [4, 5] ] ]
 *     a.flatten!   #=> [1, 2, 3, 4, 5]
 *     a.flatten!   #=> nil
 *     a            #=> [1, 2, 3, 4, 5]
 *     a = [ 1, 2, [3, [4, 5] ] ]
 *     a.flatten!(1) #=> [1, 2, 3, [4, 5]]
 */

static VALUE
rb_ary_flatten_bang(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    int mod = 0, level = -1;
    VALUE result, lv;

    rb_scan_args(argc, argv, "01", &lv);
    if (!NIL_P(lv)) level = NUM2INT(lv);
    if (level == 0) return ary;

    result = flatten(ary, level, &mod);
    if (mod == 0) return Qnil;
    rb_ary_replace(ary, result);

    return ary;
}

/*
 *  call-seq:
 *     array.flatten -> an_array
 *     array.flatten(level) -> an_array
 *
 *  Returns a new array that is a one-dimensional flattening of this
 *  array (recursively). That is, for every element that is an array,
 *  extract its elements into the new array.  If the optional
 *  <i>level</i> argument determines the level of recursion to flatten.
 *
 *     s = [ 1, 2, 3 ]           #=> [1, 2, 3]
 *     t = [ 4, 5, 6, [7, 8] ]   #=> [4, 5, 6, [7, 8]]
 *     a = [ s, t, 9, 10 ]       #=> [[1, 2, 3], [4, 5, 6, [7, 8]], 9, 10]
 *     a.flatten                 #=> [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
 *     a = [ 1, 2, [3, [4, 5] ] ]
 *     a.flatten(1)              #=> [1, 2, 3, [4, 5]]
 */

static VALUE
rb_ary_flatten(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    int mod = 0, level = -1;
    VALUE result, lv;

    rb_scan_args(argc, argv, "01", &lv);
    if (!NIL_P(lv)) level = NUM2INT(lv);
    if (level == 0) return ary;

    result = flatten(ary, level, &mod);
    if (OBJ_TAINTED(ary)) OBJ_TAINT(result);

    return result;
}

/*
 *  call-seq:
 *     array.shuffle!        -> array or nil
 *
 *  Shuffles elements in _self_ in place.
 */


static VALUE
rb_ary_shuffle_bang(ary)
    VALUE ary;
{
    long i = RARRAY(ary)->len;

    rb_ary_modify(ary);
    while (i) {
	long j = rb_genrand_real()*i;
	VALUE tmp = RARRAY(ary)->ptr[--i];
	RARRAY(ary)->ptr[i] = RARRAY(ary)->ptr[j];
	RARRAY(ary)->ptr[j] = tmp;
    }
    return ary;
}


/*
 *  call-seq:
 *     array.shuffle -> an_array
 *
 *  Returns a new array with elements of this array shuffled.
 *
 *     a = [ 1, 2, 3 ]           #=> [1, 2, 3]
 *     a.shuffle                 #=> [2, 3, 1]
 */

static VALUE
rb_ary_shuffle(ary)
    VALUE ary;
{
    ary = rb_ary_dup(ary);
    rb_ary_shuffle_bang(ary);
    return ary;
}


/*
 *  call-seq:
 *     array.sample        -> obj
 *     array.sample(n)     -> an_array
 *
 *  Choose a random element, or the random +n+ elements, fron the array.
 *  If the array is empty, the first form returns <code>nil</code>, and the
 *  second form returns an empty array.
 *
 */


static VALUE
rb_ary_sample(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE nv, result;
    int n, len, i, j;

    len = RARRAY_LEN(ary);
    if (argc == 0) {
	if (len == 0) return Qnil;
	i = rb_genrand_real()*len;
	return RARRAY_PTR(ary)[i];
    }
    rb_scan_args(argc, argv, "1", &nv);
    n = NUM2INT(nv);
    if (n >= len) return rb_ary_shuffle(ary);
    result = rb_ary_new2(n);
    for (i=0; i<n; i++) {
      retry:
	j = rb_genrand_real()*len;
	nv = LONG2NUM(j);
	for (j=0; j<i; j++) {
	    if (RARRAY_PTR(result)[j] == nv)
		goto retry;
	}
	RARRAY_PTR(result)[i] = nv;
	RARRAY(result)->len = i+1;
    }
    for (i=0; i<n; i++) {
	nv = RARRAY_PTR(result)[i];
	RARRAY_PTR(result)[i] = RARRAY_PTR(ary)[NUM2LONG(nv)];
    }
    return result;
}


/*
 *  call-seq:
 *     array.choice        -> obj
 *
 *  Choose a random element from an array.  NOTE: This method will be
 *  deprecated in future.  Use #sample instead.
 */

static VALUE
rb_ary_choice(ary)
    VALUE ary;
{
    long i, j;

    rb_warn("Array#choice is deprecated; use Array#sample");

    i = RARRAY(ary)->len;
    if (i == 0) return Qnil;
    j = rb_genrand_real()*i;
    return RARRAY(ary)->ptr[j];
}


/*
 *  call-seq:
 *     ary.cycle {|obj| block }
 *     ary.cycle(n) {|obj| block }
 *
 *  Calls <i>block</i> for each element repeatedly _n_ times or
 *  forever if none or nil is given.  If a non-positive number is
 *  given or the array is empty, does nothing.  Returns nil if the
 *  loop has finished without getting interrupted.
 *
 *     a = ["a", "b", "c"]
 *     a.cycle {|x| puts x }  # print, a, b, c, a, b, c,.. forever.
 *     a.cycle(2) {|x| puts x }  # print, a, b, c, a, b, c.
 *
 */

static VALUE
rb_ary_cycle(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    long n, i;
    VALUE nv = Qnil;

    rb_scan_args(argc, argv, "01", &nv);

    RETURN_ENUMERATOR(ary, argc, argv);
    if (NIL_P(nv)) {
        n = -1;
    }
    else {
        n = NUM2LONG(nv);
        if (n <= 0) return Qnil;
    }

    while (RARRAY(ary)->len > 0 && (n < 0 || 0 < n--)) {
        for (i=0; i<RARRAY(ary)->len; i++) {
            rb_yield(RARRAY(ary)->ptr[i]);
        }
    }
    return Qnil;
}

#define tmpbuf(n, size) rb_str_tmp_new((n)*(size))

/*
 * Recursively compute permutations of r elements of the set [0..n-1].
 * When we have a complete permutation of array indexes, copy the values
 * at those indexes into a new array and yield that array.
 *
 * n: the size of the set
 * r: the number of elements in each permutation
 * p: the array (of size r) that we're filling in
 * index: what index we're filling in now
 * used: an array of booleans: whether a given index is already used
 * values: the Ruby array that holds the actual values to permute
 */
static void
permute0(n, r, p, index, used, values)
    long n, r, *p, index;
    int *used;
    VALUE values;
{
    long i,j;
    for (i = 0; i < n; i++) {
	if (used[i] == 0) {
	    p[index] = i;
	    if (index < r-1) {             /* if not done yet */
		used[i] = 1;               /* mark index used */
		permute0(n, r, p, index+1, /* recurse */
			 used, values);
		used[i] = 0;               /* index unused */
	    }
	    else {
		/* We have a complete permutation of array indexes */
		/* Build a ruby array of the corresponding values */
		/* And yield it to the associated block */
		VALUE result = rb_ary_new2(r);
		VALUE *result_array = RARRAY(result)->ptr;
		const VALUE *values_array = RARRAY(values)->ptr;

		for (j = 0; j < r; j++) result_array[j] = values_array[p[j]];
		RARRAY(result)->len = r;
		rb_yield(result);
	    }
	}
    }
}

/*
 *  call-seq:
 *     ary.permutation { |p| block }          -> array
 *     ary.permutation                        -> enumerator
 *     ary.permutation(n) { |p| block }       -> array
 *     ary.permutation(n)                     -> enumerator
 *
 * When invoked with a block, yield all permutations of length <i>n</i>
 * of the elements of <i>ary</i>, then return the array itself.
 * If <i>n</i> is not specified, yield all permutations of all elements.
 * The implementation makes no guarantees about the order in which
 * the permutations are yielded.
 *
 * When invoked without a block, return an enumerator object instead.
 *
 * Examples:
 *
 *     a = [1, 2, 3]
 *     a.permutation.to_a     #=> [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]
 *     a.permutation(1).to_a  #=> [[1],[2],[3]]
 *     a.permutation(2).to_a  #=> [[1,2],[1,3],[2,1],[2,3],[3,1],[3,2]]
 *     a.permutation(3).to_a  #=> [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]
 *     a.permutation(0).to_a  #=> [[]] # one permutation of length 0
 *     a.permutation(4).to_a  #=> []   # no permutations of length 4
 */

static VALUE
rb_ary_permutation(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE num;
    long r, n, i;

    n = RARRAY(ary)->len;                  /* Array length */
    RETURN_ENUMERATOR(ary, argc, argv);   /* Return enumerator if no block */
    rb_scan_args(argc, argv, "01", &num);
    r = NIL_P(num) ? n : NUM2LONG(num);   /* Permutation size from argument */

    if (r < 0 || n < r) {
	/* no permutations: yield nothing */
    }
    else if (r == 0) { /* exactly one permutation: the zero-length array */
	rb_yield(rb_ary_new2(0));
    }
    else if (r == 1) { /* this is a special, easy case */
	for (i = 0; i < RARRAY(ary)->len; i++) {
	    rb_yield(rb_ary_new3(1, RARRAY(ary)->ptr[i]));
	}
    }
    else {             /* this is the general case */
	volatile VALUE t0 = tmpbuf(n,sizeof(long));
	long *p = (long*)RSTRING(t0)->ptr;
	volatile VALUE t1 = tmpbuf(n,sizeof(int));
	int *used = (int*)RSTRING(t1)->ptr;
	VALUE ary0 = ary_make_shared(ary); /* private defensive copy of ary */

	for (i = 0; i < n; i++) used[i] = 0; /* initialize array */

	permute0(n, r, p, 0, used, ary0); /* compute and yield permutations */
	RB_GC_GUARD(t0);
	RB_GC_GUARD(t1);
    }
    return ary;
}

static long
combi_len(n, k)
    long n, k;
{
    long i, val = 1;

    if (k*2 > n) k = n-k;
    if (k == 0) return 1;
    if (k < 0) return 0;
    val = 1;
    for (i=1; i <= k; i++,n--) {
	long m = val;
	val *= n;
	if (val < m) {
	    rb_raise(rb_eRangeError, "too big for combination");
	}
	val /= i;
    }
    return val;
}

/*
 *  call-seq:
 *     ary.combination(n) { |c| block }    -> ary
 *     ary.combination(n)                  -> enumerator
 *
 * When invoked with a block, yields all combinations of length <i>n</i>
 * of elements from <i>ary</i> and then returns <i>ary</i> itself.
 * The implementation makes no guarantees about the order in which
 * the combinations are yielded.
 *
 * When invoked without a block, returns an enumerator object instead.
 *
 * Examples:
 *
 *     a = [1, 2, 3, 4]
 *     a.combination(1).to_a  #=> [[1],[2],[3],[4]]
 *     a.combination(2).to_a  #=> [[1,2],[1,3],[1,4],[2,3],[2,4],[3,4]]
 *     a.combination(3).to_a  #=> [[1,2,3],[1,2,4],[1,3,4],[2,3,4]]
 *     a.combination(4).to_a  #=> [[1,2,3,4]]
 *     a.combination(0).to_a  #=> [[]] # one combination of length 0
 *     a.combination(5).to_a  #=> []   # no combinations of length 5
 *
 */

static VALUE
rb_ary_combination(ary, num)
    VALUE ary;
    VALUE num;
{
    long n, i, len;

    n = NUM2LONG(num);
    RETURN_ENUMERATOR(ary, 1, &num);
    len = RARRAY(ary)->len;
    if (n < 0 || len < n) {
	/* yield nothing */
    }
    else if (n == 0) {
	rb_yield(rb_ary_new2(0));
    }
    else if (n == 1) {
	for (i = 0; i < len; i++) {
	    rb_yield(rb_ary_new3(1, RARRAY(ary)->ptr[i]));
	}
    }
    else {
	volatile VALUE t0 = tmpbuf(n+1, sizeof(long));
	long *stack = (long*)RSTRING(t0)->ptr;
	long nlen = combi_len(len, n);
	volatile VALUE cc = rb_ary_new2(n);
	VALUE *chosen = RARRAY(cc)->ptr;
	long lev = 0;

	RBASIC(cc)->klass = 0;
	MEMZERO(stack, long, n);
	stack[0] = -1;
	for (i = 0; i < nlen; i++) {
	    chosen[lev] = RARRAY(ary)->ptr[stack[lev+1]];
	    for (lev++; lev < n; lev++) {
		chosen[lev] = RARRAY(ary)->ptr[stack[lev+1] = stack[lev]+1];
	    }
	    rb_yield(rb_ary_new4(n, chosen));
	    do {
		stack[lev--]++;
	    } while (lev && (stack[lev+1]+n == len+lev+1));
	}
    }
    return ary;
}

/*
 *  call-seq:
 *     ary.product(other_ary, ...)
 *
 *  Returns an array of all combinations of elements from all arrays.
 *  The length of the returned array is the product of the length
 *  of ary and the argument arrays
 *
 *     [1,2,3].product([4,5])     # => [[1,4],[1,5],[2,4],[2,5],[3,4],[3,5]]
 *     [1,2].product([1,2])       # => [[1,1],[1,2],[2,1],[2,2]]
 *     [1,2].product([3,4],[5,6]) # => [[1,3,5],[1,3,6],[1,4,5],[1,4,6],
 *                                #     [2,3,5],[2,3,6],[2,4,5],[2,4,6]]
 *     [1,2].product()            # => [[1],[2]]
 *     [1,2].product([])          # => []
 */

static VALUE
rb_ary_product(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    int n = argc+1;    /* How many arrays we're operating on */
    volatile VALUE t0 = ary_new(0, n);
    volatile VALUE t1 = tmpbuf(n, sizeof(int));
    VALUE *arrays = RARRAY(t0)->ptr; /* The arrays we're computing the product of */
    int *counters = (int*)RSTRING(t1)->ptr; /* The current position in each one */
    VALUE result;      /* The array we'll be returning */
    long i,j;
    long resultlen = 1;

    RBASIC(t0)->klass = 0;
    RBASIC(t1)->klass = 0;

    /* initialize the arrays of arrays */
    arrays[0] = ary;
    for (i = 1; i < n; i++) arrays[i] = to_ary(argv[i-1]);

    /* initialize the counters for the arrays */
    for (i = 0; i < n; i++) counters[i] = 0;

    /* Compute the length of the result array; return [] if any is empty */
    for (i = 0; i < n; i++) {
	long k = RARRAY(arrays[i])->len, l = resultlen;
	if (k == 0) return rb_ary_new2(0);
	resultlen *= k;
	if (resultlen < k || resultlen < l || resultlen / k != l) {
	    rb_raise(rb_eRangeError, "too big to product");
	}
    }

    /* Otherwise, allocate and fill in an array of results */
    result = rb_ary_new2(resultlen);
    for (i = 0; i < resultlen; i++) {
	int m;
	/* fill in one subarray */
	VALUE subarray = rb_ary_new2(n);
	for (j = 0; j < n; j++) {
	    rb_ary_push(subarray, rb_ary_entry(arrays[j], counters[j]));
	}

	/* put it on the result array */
	rb_ary_push(result, subarray);

	/*
	 * Increment the last counter.  If it overflows, reset to 0
	 * and increment the one before it.
	 */
	m = n-1;
	counters[m]++;
	while (m > 0 && counters[m] == RARRAY(arrays[m])->len) {
	    counters[m] = 0;
	    m--;
	    counters[m]++;
	}
    }

    return result;
}

/*
 *  call-seq:
 *     ary.take(n)               => array
 *
 *  Returns first n elements from <i>ary</i>.
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.take(3)             # => [1, 2, 3]
 *
 */

static VALUE
rb_ary_take(obj, n)
    VALUE obj;
    VALUE n;
{
    long len = NUM2LONG(n);
    if (len < 0) {
	rb_raise(rb_eArgError, "attempt to take negative size");
    }

    return rb_ary_subseq(obj, 0, len);
}

/*
 *  call-seq:
 *     ary.take_while {|arr| block }   => array
 *
 *  Passes elements to the block until the block returns nil or false,
 *  then stops iterating and returns an array of all prior elements.
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.take_while {|i| i < 3 }   # => [1, 2]
 *
 */

static VALUE
rb_ary_take_while(ary)
    VALUE ary;
{
    long i;

    RETURN_ENUMERATOR(ary, 0, 0);
    for (i = 0; i < RARRAY(ary)->len; i++) {
	if (!RTEST(rb_yield(RARRAY(ary)->ptr[i]))) break;
    }
    return rb_ary_take(ary, LONG2FIX(i));
}

/*
 *  call-seq:
 *     ary.drop(n)               => array
 *
 *  Drops first n elements from <i>ary</i>, and returns rest elements
 *  in an array.
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.drop(3)             # => [4, 5, 0]
 *
 */

static VALUE
rb_ary_drop(ary, n)
    VALUE ary;
    VALUE n;
{
    VALUE result;
    long pos = NUM2LONG(n);
    if (pos < 0) {
	rb_raise(rb_eArgError, "attempt to drop negative size");
    }

    result = rb_ary_subseq(ary, pos, RARRAY(ary)->len);
    if (result == Qnil) result = rb_ary_new();
    return result;
}

/*
 *  call-seq:
 *     ary.drop_while {|arr| block }   => array
 *
 *  Drops elements up to, but not including, the first element for
 *  which the block returns nil or false and returns an array
 *  containing the remaining elements.
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.drop_while {|i| i < 3 }   # => [3, 4, 5, 0]
 *
 */

static VALUE
rb_ary_drop_while(ary)
    VALUE ary;
{
    long i;

    RETURN_ENUMERATOR(ary, 0, 0);
    for (i = 0; i < RARRAY(ary)->len; i++) {
	if (!RTEST(rb_yield(RARRAY(ary)->ptr[i]))) break;
    }
    return rb_ary_drop(ary, LONG2FIX(i));
}



/* Arrays are ordered, integer-indexed collections of any object.
 * Array indexing starts at 0, as in C or Java.  A negative index is
 * assumed to be relative to the end of the array---that is, an index of -1
 * indicates the last element of the array, -2 is the next to last
 * element in the array, and so on.
 */

void
Init_Array()
{
    rb_cArray  = rb_define_class("Array", rb_cObject);
    rb_include_module(rb_cArray, rb_mEnumerable);

    rb_define_alloc_func(rb_cArray, ary_alloc);
    rb_define_singleton_method(rb_cArray, "[]", rb_ary_s_create, -1);
    rb_define_singleton_method(rb_cArray, "try_convert", rb_ary_s_try_convert, 1);
    rb_define_method(rb_cArray, "initialize", rb_ary_initialize, -1);
    rb_define_method(rb_cArray, "initialize_copy", rb_ary_replace, 1);

    rb_define_method(rb_cArray, "to_s", rb_ary_to_s, 0);
    rb_define_method(rb_cArray, "inspect", rb_ary_inspect, 0);
    rb_define_method(rb_cArray, "to_a", rb_ary_to_a, 0);
    rb_define_method(rb_cArray, "to_ary", rb_ary_to_ary_m, 0);
    rb_define_method(rb_cArray, "frozen?",  rb_ary_frozen_p, 0);

    rb_define_method(rb_cArray, "==", rb_ary_equal, 1);
    rb_define_method(rb_cArray, "eql?", rb_ary_eql, 1);
    rb_define_method(rb_cArray, "hash", rb_ary_hash, 0);

    rb_define_method(rb_cArray, "[]", rb_ary_aref, -1);
    rb_define_method(rb_cArray, "[]=", rb_ary_aset, -1);
    rb_define_method(rb_cArray, "at", rb_ary_at, 1);
    rb_define_method(rb_cArray, "fetch", rb_ary_fetch, -1);
    rb_define_method(rb_cArray, "first", rb_ary_first, -1);
    rb_define_method(rb_cArray, "last", rb_ary_last, -1);
    rb_define_method(rb_cArray, "concat", rb_ary_concat, 1);
    rb_define_method(rb_cArray, "<<", rb_ary_push, 1);
    rb_define_method(rb_cArray, "push", rb_ary_push_m, -1);
    rb_define_method(rb_cArray, "pop", rb_ary_pop_m, -1);
    rb_define_method(rb_cArray, "shift", rb_ary_shift_m, -1);
    rb_define_method(rb_cArray, "unshift", rb_ary_unshift_m, -1);
    rb_define_method(rb_cArray, "insert", rb_ary_insert, -1);
    rb_define_method(rb_cArray, "each", rb_ary_each, 0);
    rb_define_method(rb_cArray, "each_index", rb_ary_each_index, 0);
    rb_define_method(rb_cArray, "reverse_each", rb_ary_reverse_each, 0);
    rb_define_method(rb_cArray, "length", rb_ary_length, 0);
    rb_define_alias(rb_cArray,  "size", "length");
    rb_define_method(rb_cArray, "empty?", rb_ary_empty_p, 0);
    rb_define_method(rb_cArray, "find_index", rb_ary_index, -1);
    rb_define_method(rb_cArray, "index", rb_ary_index, -1);
    rb_define_method(rb_cArray, "rindex", rb_ary_rindex, -1);
    rb_define_method(rb_cArray, "indexes", rb_ary_indexes, -1);
    rb_define_method(rb_cArray, "indices", rb_ary_indexes, -1);
    rb_define_method(rb_cArray, "join", rb_ary_join_m, -1);
    rb_define_method(rb_cArray, "reverse", rb_ary_reverse_m, 0);
    rb_define_method(rb_cArray, "reverse!", rb_ary_reverse_bang, 0);
    rb_define_method(rb_cArray, "sort", rb_ary_sort, 0);
    rb_define_method(rb_cArray, "sort!", rb_ary_sort_bang, 0);
    rb_define_method(rb_cArray, "collect", rb_ary_collect, 0);
    rb_define_method(rb_cArray, "collect!", rb_ary_collect_bang, 0);
    rb_define_method(rb_cArray, "map", rb_ary_collect, 0);
    rb_define_method(rb_cArray, "map!", rb_ary_collect_bang, 0);
    rb_define_method(rb_cArray, "select", rb_ary_select, 0);
    rb_define_method(rb_cArray, "values_at", rb_ary_values_at, -1);
    rb_define_method(rb_cArray, "delete", rb_ary_delete, 1);
    rb_define_method(rb_cArray, "delete_at", rb_ary_delete_at_m, 1);
    rb_define_method(rb_cArray, "delete_if", rb_ary_delete_if, 0);
    rb_define_method(rb_cArray, "reject", rb_ary_reject, 0);
    rb_define_method(rb_cArray, "reject!", rb_ary_reject_bang, 0);
    rb_define_method(rb_cArray, "zip", rb_ary_zip, -1);
    rb_define_method(rb_cArray, "transpose", rb_ary_transpose, 0);
    rb_define_method(rb_cArray, "replace", rb_ary_replace, 1);
    rb_define_method(rb_cArray, "clear", rb_ary_clear, 0);
    rb_define_method(rb_cArray, "fill", rb_ary_fill, -1);
    rb_define_method(rb_cArray, "include?", rb_ary_includes, 1);
    rb_define_method(rb_cArray, "<=>", rb_ary_cmp, 1);

    rb_define_method(rb_cArray, "slice", rb_ary_aref, -1);
    rb_define_method(rb_cArray, "slice!", rb_ary_slice_bang, -1);

    rb_define_method(rb_cArray, "assoc", rb_ary_assoc, 1);
    rb_define_method(rb_cArray, "rassoc", rb_ary_rassoc, 1);

    rb_define_method(rb_cArray, "+", rb_ary_plus, 1);
    rb_define_method(rb_cArray, "*", rb_ary_times, 1);

    rb_define_method(rb_cArray, "-", rb_ary_diff, 1);
    rb_define_method(rb_cArray, "&", rb_ary_and, 1);
    rb_define_method(rb_cArray, "|", rb_ary_or, 1);

    rb_define_method(rb_cArray, "uniq", rb_ary_uniq, 0);
    rb_define_method(rb_cArray, "uniq!", rb_ary_uniq_bang, 0);
    rb_define_method(rb_cArray, "compact", rb_ary_compact, 0);
    rb_define_method(rb_cArray, "compact!", rb_ary_compact_bang, 0);
    rb_define_method(rb_cArray, "flatten", rb_ary_flatten, -1);
    rb_define_method(rb_cArray, "flatten!", rb_ary_flatten_bang, -1);
    rb_define_method(rb_cArray, "nitems", rb_ary_nitems, 0);
    rb_define_method(rb_cArray, "count", rb_ary_count, -1);
    rb_define_method(rb_cArray, "shuffle!", rb_ary_shuffle_bang, 0);
    rb_define_method(rb_cArray, "shuffle", rb_ary_shuffle, 0);
    rb_define_method(rb_cArray, "sample", rb_ary_sample, -1);
    rb_define_method(rb_cArray, "choice", rb_ary_choice, 0);
    rb_define_method(rb_cArray, "cycle", rb_ary_cycle, -1);
    rb_define_method(rb_cArray, "permutation", rb_ary_permutation, -1);
    rb_define_method(rb_cArray, "combination", rb_ary_combination, 1);
    rb_define_method(rb_cArray, "product", rb_ary_product, -1);

    rb_define_method(rb_cArray, "take", rb_ary_take, 1);
    rb_define_method(rb_cArray, "take_while", rb_ary_take_while, 0);
    rb_define_method(rb_cArray, "drop", rb_ary_drop, 1);
    rb_define_method(rb_cArray, "drop_while", rb_ary_drop_while, 0);

    id_cmp = rb_intern("<=>");
    inspect_key = rb_intern("__inspect_key__");
}
