# frozen_string_literal: false
require 'mkmf'

have_type("enum rb_io_mode", "ruby/io.h")

create_makefile('stringio')
