require 'mkmf'
require 'rbconfig'

have_header("re.h")
create_makefile 'json/ext/parser'
