require 'mkmf'

dir_config("dbm")
if have_library("gdbm", "dbm_open")
  gdbm = true
end
gdbm or have_library("db", "dbm_open") or have_library("dbm", "dbm_open")
have_header("cdefs.h") 
have_header("sys/cdefs.h") 
if have_header("ndbm.h") and have_func("dbm_open")
  have_func("dbm_clearerr") unless gdbm
  create_makefile("dbm")
end
