require 'mkmf'

case RUBY_ENGINE
when 'jruby', 'truffleruby'
  File.write('Makefile', dummy_makefile($srcdir).join)
else
  create_makefile 'erb/escape'
end
