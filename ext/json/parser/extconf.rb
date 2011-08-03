require 'mkmf'
require 'rbconfig'

if RUBY_VERSION < "1.9"
  have_header("re.h")
else
  have_header("ruby/re.h")
  have_header("ruby/encoding.h")
end
create_makefile 'json/ext/parser'
