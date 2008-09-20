require 'mkmf'
require 'rbconfig'

if CONFIG['CC'] =~ /gcc/
  $CFLAGS += ' -Wall'
  #$CFLAGS += ' -O0 -ggdb'
end

create_makefile 'parser'
