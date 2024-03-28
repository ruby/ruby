# frozen_string_literal: true
$INCFLAGS << " -I$(topdir) -I$(top_srcdir)"
$VPATH << '$(topdir)' << '$(top_srcdir)' # for id.h.

have_func("tmpfile_s")
have_func("tmpfile")

create_makefile('objspace')
