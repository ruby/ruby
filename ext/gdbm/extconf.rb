require 'mkmf'
$LDFLAGS = "-L/usr/local/lib"
have_library("gdbm", "gdbm_open")
have_header("gdbm.h")
if have_func("gdbm_open")
  create_makefile("gdbm")
end
