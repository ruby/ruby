# frozen_string_literal: false
require 'mkmf'
$VPATH << '$(topdir)' << '$(top_srcdir)'
$INCFLAGS << " -I$(topdir) -I$(top_srcdir)"
create_makefile('coverage')
