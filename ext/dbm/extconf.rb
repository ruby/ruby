require 'mkmf'

dir_config("dbm")

if dblib = with_config("dbm-type", nil)
  dblib = dblib.split(/[ ,]+/)
else
  dblib = %w(db db2 db1 db5 db4 db3 dbm gdbm gdbm_compat qdbm)
end

headers = {
  "db" => ["db.h"],
  "db1" => ["db1/ndbm.h", "db1.h", "ndbm.h"],
  "db2" => ["db2/db.h", "db2.h", "db.h"],
  "db3" => ["db3/db.h", "db3.h", "db.h"],
  "db4" => ["db4/db.h", "db4.h", "db.h"],
  "db5" => ["db5/db.h", "db5.h", "db.h"],
  "dbm" => ["ndbm.h"],
  "gdbm" => ["gdbm-ndbm.h", "ndbm.h", "gdbm/ndbm.h"],
  "gdbm_compat" => ["gdbm-ndbm.h", "ndbm.h", "gdbm/ndbm.h"],
  "qdbm" => ["relic.h", "qdbm/relic.h"],
}

def headers.db_check(db)
  db_prefix = nil
  have_gdbm = false
  hsearch = nil

  case db
  when /^db[2-5]?$/
    db_prefix = "__db_n"
    hsearch = "-DDB_DBM_HSEARCH "
  when "gdbm"
    have_gdbm = true
  when "gdbm_compat"
    have_gdbm = true
    have_library("gdbm") or return false
  end
  db_prefix ||= ""

  if (have_library(db, db_prefix+"dbm_open") || have_func(db_prefix+"dbm_open")) and
      hdr = self.fetch(db, ["ndbm.h"]).find {|h| have_type("DBM", h, hsearch)} or
      hdr = self.fetch(db, ["ndbm.h"]).find {|h| have_type("DBM", ["db.h", h], hsearch)}
    have_func(db_prefix+"dbm_clearerr") unless have_gdbm
    $defs << hsearch if hsearch
    $defs << '-DDBM_HDR="<'+hdr+'>"'
    true
  else
    false
  end
end

if dblib.any? {|db| headers.db_check(db)}
  have_header("cdefs.h")
  have_header("sys/cdefs.h")
  create_makefile("dbm")
end
