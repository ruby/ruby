require 'mkmf'
$VPATH << "$(top_srcdir)"
$INCFLAGS << " -I$(top_srcdir)"
create_makefile("probeprofiler")
