require 'mkmf'
require 'rbconfig'

if CONFIG['GCC'] == 'yes'
  $CFLAGS += ' -Wall'
  #$CFLAGS += ' -O0 -ggdb'
end

create_makefile 'json/ext/parser'
