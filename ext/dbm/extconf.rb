require 'mkmf'

dir_config("dbm")

dblib = with_config("dbm-type", nil)

$dbm_conf_headers = {
  "db" => ["db.h"],
  "db1" => ["db1/ndbm.h", "db1.h", "ndbm.h"],
  "db2" => ["db2/db.h", "db2.h", "db.h"],
  "dbm" => ["ndbm.h"],
  "gdbm" => ["gdbm-ndbm.h", "ndbm.h"],
  "gdbm_compat" => ["gdbm-ndbm.h", "ndbm.h"],
}

def db_check(db)
  $dbm_conf_db_prefix = ""
  $dbm_conf_have_gdbm = false
  hsearch = ""

  case db
  when /^db2?$/
    $dbm_conf_db_prefix = "__db_n"
    hsearch = "-DDB_DBM_HSEARCH "
  when "gdbm"
    $dbm_conf_have_gdbm = true
  when "gdbm_compat"
    $dbm_conf_have_gdbm = true
    have_library("gdbm") or return false
  end

  if have_library(db, db_prefix("dbm_open")) || have_func(db_prefix("dbm_open"))
    for hdr in $dbm_conf_headers.fetch(db, ["ndbm.h"])
      if have_header(hdr.dup)
	$CFLAGS += " " + hsearch + "-DDBM_HDR='<"+hdr+">'"
	return true
      end
    end
  end
  return false
end

def db_prefix(func)
  $dbm_conf_db_prefix+func
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
if /DBM_HDR/ =~ $CFLAGS and have_func(db_prefix("dbm_open"))
  have_func(db_prefix("dbm_clearerr")) unless $dbm_conf_have_gdbm
  create_makefile("dbm")
end
