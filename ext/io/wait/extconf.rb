# frozen_string_literal: false
require 'mkmf'

have_func("rb_io_wait", "ruby/io.h")
have_func("rb_io_descriptor", "ruby/io.h")
create_makefile("io/wait")
