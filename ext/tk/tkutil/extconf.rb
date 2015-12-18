# frozen_string_literal: false
begin
  require 'mkmf'

  have_func("rb_obj_instance_exec", "ruby.h")
  have_func("rb_obj_untrust", "ruby.h")
  have_func("rb_obj_taint", "ruby.h")
  have_func("rb_sym2str", "ruby.h")
  have_func("rb_id2str", "ruby.h")
  have_func("rb_ary_cat", "ruby.h")
  have_func("strndup", "string.h")

  create_makefile('tkutil')
end
