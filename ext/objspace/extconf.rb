# frozen_string_literal: false
$INCFLAGS << " -I$(topdir) -I$(top_srcdir)"
$VPATH << '$(topdir)' << '$(top_srcdir)' # for id.h.
create_makefile('objspace')
