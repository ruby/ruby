require 'mkmf'

if RUBY_ENGINE == 'truffleruby'
  File.write("Makefile", dummy_makefile($srcdir).join(""))
else
  create_makefile 'cgi/escape'
end
