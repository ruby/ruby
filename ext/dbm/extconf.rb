$LDFLAGS = "-L/usr/local/lib"
have_library("gdbm", "dbm_open") or have_library("dbm", "dbm_open")
if have_func("dbm_open")
  create_makefile("dbm")
end
