require 'mkmf'
$LDFLAGS = "-L/usr/local/lib"
if have_library("gdbm", "gdbm_open") and
   have_header("gdbm.h") and
   have_func("gdbm_open") then
  create_makefile("gdbm")
end
