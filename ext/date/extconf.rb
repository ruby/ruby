require 'mkmf'
$INCFLAGS << " -I$(top_srcdir)"
create_makefile('date_core')
