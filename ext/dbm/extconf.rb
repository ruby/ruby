have_library("dbm", "dbm_open")
if have_func("dbm_open")
  create_makefile("dbm")
end
