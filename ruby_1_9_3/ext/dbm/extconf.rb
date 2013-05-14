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

# BEGIN BACKPORTED FROM 2.0
class String
  # Wraps a string in escaped quotes if it contains whitespace.
  def quote
    /\s/ =~ self ? "\"#{self}\"" : "#{self}"
  end

  # Generates a string used as cpp macro name.
  def tr_cpp
    strip.upcase.tr_s("^A-Z0-9_*", "_").tr_s("*", "P")
  end

  def funcall_style
    /\)\z/ =~ self ? dup : "#{self}()"
  end

  def sans_arguments
    self[/\A[^()]+/]
  end
end

  def rm_f(*files)
    opt = (Hash === files.last ? [files.pop] : [])
    FileUtils.rm_f(Dir[*files.flatten], *opt)
  end

  def try_func(func, libs, headers = nil, opt = "", &b)
    headers = cpp_include(headers)
    case func
    when /^&/
      decltype = proc {|x|"const volatile void *#{x}"}
    when /\)$/
      call = func
    else
      call = "#{func}()"
      decltype = proc {|x| "void ((*#{x})())"}
    end
    if opt and !opt.empty?
      [[:to_str], [:join, " "], [:to_s]].each do |meth, *args|
        if opt.respond_to?(meth)
          break opt = opt.send(meth, *args)
        end
      end
      opt = "#{opt} #{libs}"
    else
      opt = libs
    end
    decltype && try_link(<<"SRC", opt, &b) or
#{headers}
/*top*/
#{MAIN_DOES_NOTHING}
extern int t(void);
int t(void) { #{decltype["volatile p"]}; p = (#{decltype[]})#{func}; return 0; }
SRC
    call && try_link(<<"SRC", opt, &b)
#{headers}
/*top*/
#{MAIN_DOES_NOTHING}
extern int t(void);
int t(void) { #{call}; return 0; }
SRC
  end

  def try_var(var, headers = nil, opt = "", &b)
    headers = cpp_include(headers)
    try_compile(<<"SRC", opt, &b)
#{headers}
/*top*/
#{MAIN_DOES_NOTHING}
extern int t(void);
int t(void) { const volatile void *volatile p; p = &(&#{var})[0]; return 0; }
SRC
  end

  def have_library(lib, func = nil, headers = nil, opt = "", &b)
    func = "main" if !func or func.empty?
    lib = with_config(lib+'lib', lib)
    checking_for checking_message(func.funcall_style, LIBARG%lib, opt) do
      if COMMON_LIBS.include?(lib)
        true
      else
        libs = append_library($libs, lib)
        if try_func(func, libs, headers, opt, &b)
          $libs = libs
          true
        else
          false
        end
      end
    end
  end

  def have_func(func, headers = nil, opt = "", &b)
    checking_for checking_message(func.funcall_style, headers, opt) do
      if try_func(func, $libs, headers, opt, &b)
        $defs << "-DHAVE_#{func.sans_arguments.tr_cpp}"
        true
      else
        false
      end
    end
  end

  def have_var(var, headers = nil, opt = "", &b)
    checking_for checking_message(var, headers, opt) do
      if try_var(var, headers, opt, &b)
        $defs.push(format("-DHAVE_%s", var.tr_cpp))
        true
      else
        false
      end
    end
  end

  def try_cpp(src, opt="", *opts, &b)
    try_do(src, cpp_command(CPPOUTFILE, opt), *opts, &b)
  ensure
    rm_f "conftest*"
  end

  alias :try_header :try_cpp

  def have_header(header, preheaders = nil, opt = "", &b)
    checking_for header do
      if try_header(cpp_include(preheaders)+cpp_include(header), opt, &b)
        $defs.push(format("-DHAVE_%s", header.tr_cpp))
        true
      else
        false
      end
    end
  end

  def convertible_int(type, headers = nil, opts = nil, &b)
    type, macname = *type
    checking_for("convertible type of #{type}", STRING_OR_FAILED_FORMAT) do
      if UNIVERSAL_INTS.include?(type)
        type
      else
        typedef, member, prelude = typedef_expr(type, headers, &b)
        if member
          prelude << "static rbcv_typedef_ rbcv_var;"
          compat = UNIVERSAL_INTS.find {|t|
            try_static_assert("sizeof(rbcv_var.#{member}) == sizeof(#{t})", [prelude], opts, &b)
          }
        else
          next unless signed = try_signedness(typedef, member, [prelude])
          u = "unsigned " if signed > 0
          prelude << "extern rbcv_typedef_ foo();"
          compat = UNIVERSAL_INTS.find {|t|
            try_compile([prelude, "extern #{u}#{t} foo();"].join("\n"), opts, :werror=>true, &b)
          }
        end
        if compat
          macname ||= type.sub(/_(?=t\z)/, '').tr_cpp
          conv = (compat == "long long" ? "LL" : compat.upcase)
          compat = "#{u}#{compat}"
          typename = type.tr_cpp
          $defs.push(format("-DSIZEOF_%s=SIZEOF_%s", typename, compat.tr_cpp))
          $defs.push(format("-DTYPEOF_%s=%s", typename, compat.quote))
          $defs.push(format("-DPRI_%s_PREFIX=PRI_%s_PREFIX", macname, conv))
          conv = (u ? "U" : "") + conv
          $defs.push(format("-D%s2NUM=%s2NUM", macname, conv))
          $defs.push(format("-DNUM2%s=NUM2%s", macname, conv))
          compat
        end
      end
    end
  end
# END BACKPORTED FROM 2.0

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
  hsearch = nil

  case db
  when /^db[2-5]?$/
    hsearch = "-DDB_DBM_HSEARCH"
  when "gdbm_compat"
    have_library("gdbm") or return false
  end

  if have_type("DBM", hdr, hsearch) and
     (db == 'libc' ? have_func('dbm_open("", 0, 0)', hdr, hsearch) :
                     have_library(db, 'dbm_open("", 0, 0)', hdr, hsearch)) and
     have_func('dbm_clearerr((DBM *)0)', hdr, hsearch) and
     (/\Adb\d?\z/ =~ db || db == 'libc' || !have_macro('_DB_H_', hdr, hsearch)) # _DB_H_ should not be defined except Berkeley DB.
    case db
    when /\Adb\d?\z/
      have_func('db_version((int *)0, (int *)0, (int *)0)', hdr, hsearch)
    when /\Agdbm/
      have_var("gdbm_version", hdr, hsearch)
      # gdbm_version is not declared by ndbm.h until gdbm 1.8.3.
      # We can't include ndbm.h and gdbm.h because they both define datum type.
      # ndbm.h includes gdbm.h and gdbm_version is declared since gdbm 1.9.
      have_libvar(["gdbm_version", "char *"], hdr, hsearch)
    when /\Aqdbm\z/
      have_var("dpversion", hdr, hsearch)
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
  have_func("dbm_pagfno((DBM *)0)", headers.found, headers.defs)
  have_func("dbm_dirfno((DBM *)0)", headers.found, headers.defs)
  convertible_int("datum.dsize", headers.found, headers.defs)
  create_makefile("dbm")
end
