require 'mkmf'
$LDFLAGS = "-L/usr/local/lib"
if dir = with_config("dbm-include")
  $CFLAGS = "-I#{dir}"
end
have_library("gdbm", "dbm_open") or
  have_library("db", "dbm_open") or
  have_library("dbm", "dbm_open")
have_header("cdefs.h") 
if have_header("ndbm.h") and have_func("dbm_open")
  have_func("dbm_clearerr")
  create_makefile("dbm")
end
