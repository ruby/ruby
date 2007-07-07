require 'mkmf'
require 'rbconfig'

if CONFIG['CC'] =~ /gcc/
  #$CFLAGS += ' -Wall -ggdb'
  $CFLAGS += ' -Wall'
end

have_header 'st.h'
create_makefile 'json/ext/parser'
