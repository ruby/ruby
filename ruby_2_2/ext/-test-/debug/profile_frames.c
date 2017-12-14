#include "ruby/ruby.h"
#include "ruby/debug.h"

#define MAX_BUF_SIZE 0x100

static VALUE
profile_frames(VALUE self, VALUE start_v, VALUE num_v)
{
    int i, collected_size;
    int start = NUM2INT(start_v);
    int buff_size = NUM2INT(num_v);
    VALUE buff[MAX_BUF_SIZE];
    int lines[MAX_BUF_SIZE];
    VALUE result = rb_ary_new();

    if (buff_size > MAX_BUF_SIZE) rb_raise(rb_eRuntimeError, "too long buff_size");

    collected_size = rb_profile_frames(start, buff_size, buff, lines);

    for (i=0; i<collected_size; i++) {
	VALUE ary = rb_ary_new();
	rb_ary_push(ary, rb_profile_frame_path(buff[i]));
	rb_ary_push(ary, rb_profile_frame_absolute_path(buff[i]));
	rb_ary_push(ary, rb_profile_frame_label(buff[i]));
	rb_ary_push(ary, rb_profile_frame_base_label(buff[i]));
	rb_ary_push(ary, rb_profile_frame_full_label(buff[i]));
	rb_ary_push(ary, rb_profile_frame_first_lineno(buff[i]));
	rb_ary_push(ary, rb_profile_frame_classpath(buff[i]));
	rb_ary_push(ary, rb_profile_frame_singleton_method_p(buff[i]));
	rb_ary_push(ary, rb_profile_frame_method_name(buff[i]));
	rb_ary_push(ary, rb_profile_frame_qualified_method_name(buff[i]));

	rb_ary_push(result, ary);
    }

    return result;
}

void
Init_profile_frames(VALUE klass)
{
    rb_define_module_function(klass, "profile_frames", profile_frames, 2);
}
