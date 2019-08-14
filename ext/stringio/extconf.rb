# frozen_string_literal: false
require 'mkmf'
have_func("rb_io_extract_modeenc", "ruby/io.h")
create_makefile('stringio')
