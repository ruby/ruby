require 'mkmf'

dir_config("dbm")

if dblib = with_config("dbm-type", nil)
  dblib = dblib.split(/[ ,]+/)
else
  dblib = %w(libc db db2 db1 db5 db4 db3 dbm gdbm gdbm_compat qdbm)
end

headers = {
  "libc" => ["ndbm.h"], # 4.4BSD libc contains Berkeley DB 1.
  "db" => ["db.h"],
  "db1" => ["db1/ndbm.h", "db1.h", "ndbm.h"],
  "db2" => ["db2/db.h", "db2.h", "db.h"],
  "db3" => ["db3/db.h", "db3.h", "db.h"],
  "db4" => ["db4/db.h", "db4.h", "db.h"],
  "db5" => ["db5/db.h", "db5.h", "db.h"],
  "dbm" => ["ndbm.h"], # traditional ndbm (4.3BSD)
  "gdbm" => ["gdbm-ndbm.h", "ndbm.h", "gdbm/ndbm.h"], # gdbm until 1.8.0
  "gdbm_compat" => ["gdbm-ndbm.h", "ndbm.h", "gdbm/ndbm.h"], # gdbm since 1.8.1
  "qdbm" => ["relic.h", "qdbm/relic.h"],
}

class << headers
  attr_accessor :found
  attr_accessor :defs
end
headers.found = []
headers.defs = nil

def headers.db_check(db, hdr)
  old_libs = $libs.dup
  old_defs = $defs.dup
  result = db_check2(db, hdr)
  if !result
    $libs = old_libs
    $defs = old_defs
  end
  result
end

def have_libvar(var, headers = nil, opt = "", &b)
  checking_for checking_message([*var].compact.join(' '), headers, opt) do
    try_libvar(var, headers, opt, &b)
  end
end

def try_libvar(var, headers = nil, opt = "", &b)
  var, type = *var
  if try_link(<<"SRC", opt, &b)
#{cpp_include(headers)}
/*top*/
int main(int argc, char *argv[]) {
  typedef #{type || 'int'} conftest_type;
  extern conftest_type #{var};
  conftest_type *conftest_var = &#{var};
  return 0;
}
SRC
    $defs.push(format("-DHAVE_LIBVAR_%s", var.tr_cpp))
    true
  else
    false
  end
end


def headers.db_check2(db, hdr)
  db_prefix = ''
  have_gdbm = false
  hsearch = nil

  case db
  when /^db[2-5]?$/
    db_prefix = "__db_n"
    hsearch = "-DDB_DBM_HSEARCH"
  when "gdbm"
    have_gdbm = true
  when "gdbm_compat"
    have_gdbm = true
    have_library("gdbm") or return false
  end

  if (have_library(db, db_prefix+"dbm_open") || have_func(db_prefix+"dbm_open")) and
      hdr = self.fetch(db, ["ndbm.h"]).find {|h| have_type("DBM", h, hsearch)} or
      hdr = self.fetch(db, ["ndbm.h"]).find {|h| have_type("DBM", ["db.h", h], hsearch)}
    have_func(db_prefix+"dbm_clearerr") unless have_gdbm
    $defs << hsearch if hsearch
    case db
    when /\Adb\d?\z/
      have_func('db_version')
    when /\Agdbm/
      have_var("gdbm_version", hdr)
      # gdbm_version is not declared by ndbm.h until gdbm 1.8.3.
      # We can't include ndbm.h and gdbm.h because they both define datum type.
      # ndbm.h includes gdbm.h and gdbm_version is declared since gdbm 1.9.
      have_libvar(["gdbm_version", "char *"], hdr)
    when /\Aqdbm\z/
      have_var("dpversion", hdr)
    end
    if hsearch
      $defs << hsearch
      @defs = hsearch
    end
    $defs << '-DDBM_HDR="<'+hdr+'>"'
    @found << hdr
    true
  else
    false
  end
end

if dblib.any? {|db| headers.fetch(db, ["ndbm.h"]).any? {|hdr| headers.db_check(db, hdr) } }
  have_header("cdefs.h")
  have_header("sys/cdefs.h")
  create_makefile("dbm")
end
