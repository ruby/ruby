require 'mkmf'
$CFLAGS += " -DHAVE_CONFIG_H"
create_makefile('md5')
