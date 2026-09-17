# frozen_string_literal: true
require 'mkmf'

config_string("strict_warnflags") {|w| $warnflags += " #{w}"}

unless try_compile("", "", werror: true)
  append_cflags("-Wno-default-const-init-field-unsafe")
end
append_cflags("-Wno-compound-token-split-by-macro") if RUBY_VERSION < "2.7."
have_func("rb_category_warn")
with_werror("", {:werror => true}) do |opt, |
  have_var("timezone", "time.h", opt)
  have_var("altzone", "time.h", opt)
end

have_func("rb_gc_mark_movable", "ruby.h") # RUBY_VERSION >= 2.7
have_const("RUBY_TYPED_EMBEDDABLE", "ruby.h") # RUBY_VERSION >= 3.3

create_makefile('date_core')
