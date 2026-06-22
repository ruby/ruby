require 'mkmf'

case RUBY_ENGINE
when 'jruby', 'truffleruby'
  File.write('Makefile', dummy_makefile($srcdir).join)
else
  have_func("rb_ext_ractor_safe", "ruby.h")
  create_makefile 'erb/escape'
end
