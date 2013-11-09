$INCFLAGS << " -I$(topdir) -I$(top_srcdir)"
have_func("mkstemp")
create_makefile('objspace')
