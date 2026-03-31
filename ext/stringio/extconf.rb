# frozen_string_literal: false
require 'mkmf'
if RUBY_ENGINE == 'ruby'
  have_type("rb_io_mode_t", "ruby/io.h")

  create_makefile('stringio')
else
  File.write('Makefile', dummy_makefile("").join)
end
