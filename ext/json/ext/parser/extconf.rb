require 'mkmf'
require 'rbconfig'

if CONFIG['CC'] =~ /gcc/
  #CONFIG['CC'] += ' -Wall -ggdb'
  CONFIG['CC'] += ' -Wall'
end

have_header 'st.h'
create_makefile 'json/ext/parser'
