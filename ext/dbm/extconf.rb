require 'mkmf'

dir_config("dbm")

$db_hdr = "ndbm.h"
$db_prefix = ""
dblib = with_config("dbm-type", nil)

def db_check(db)
  if /^db2?$/ =~ db
    $db_prefix = "__db_n"
    $db_hdr = db+".h"
  end
  r = have_library(db, db_prefix("dbm_open"))
  if db == "gdbm"
    $have_gdbm = true
  end
  return r
end

def db_prefix(func)
  $db_prefix+func
end

if dblib
  db_check(dblib)
else
  for dblib in %w(db db2 db1 dbm gdbm)
    db_check(dblib) and break
  end
end

have_header("cdefs.h") 
have_header("sys/cdefs.h") 
if have_header($db_hdr) and have_func(db_prefix("dbm_open"))
  have_func(db_prefix("dbm_clearerr")) unless $have_gdbm
  create_makefile("dbm")
end
