# frozen_string_literal: false
require 'mkmf'

have_func("labs", "stdlib.h")
have_func("llabs", "stdlib.h")

have_type("struct RRational", "ruby.h")
have_func("rb_rational_num", "ruby.h")
have_func("rb_rational_den", "ruby.h")

create_makefile('bigdecimal')
