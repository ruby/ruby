require "envutil"

class TestExtLibs < Test::Unit::TestCase
  def self.check_existence(ext, add_msg = nil)
    add_msg = ".  #{add_msg}" if add_msg
    define_method("test_existence_of_#{ext}") do
      assert_separately([], <<-"end;", ignore_stderr: true) # do
        assert_nothing_raised("extension library `#{ext}' is not found#{add_msg}") do
          require "#{ext}"
        end
      end;
    end
  end

  def windows?
    /mswin|mingw/ =~ RUBY_PLATFORM
  end

  check_existence "bigdecimal"
  check_existence "continuation"
  check_existence "coverage"
  check_existence "date"
  #check_existence "dbm" # depend on libdbm
  check_existence "digest"
  check_existence "digest/bubblebabble"
  check_existence "digest/md5"
  check_existence "digest/rmd160"
  check_existence "digest/sha1"
  check_existence "digest/sha2"
  check_existence "etc"
  check_existence "fcntl"
  check_existence "fiber"
  check_existence "fiddle"
  #check_existence "gdbm" # depend on libgdbm
  check_existence "io/console"
  check_existence "io/nonblock"
  check_existence "io/wait"
  check_existence "json"
  check_existence "mathn/complex"
  check_existence "mathn/rational"
  check_existence "nkf"
  check_existence "objspace"
  check_existence "openssl", "this may be false positive, but should assert because rubygems requires this"
  check_existence "pathname"
  check_existence "psych"
  check_existence "pty" unless windows?
  check_existence "racc/cparse"
  check_existence "rbconfig/sizeof"
  #check_existence "readline" # depend on libreadline
  check_existence "ripper"
  check_existence "sdbm"
  check_existence "socket"
  check_existence "stringio"
  check_existence "strscan"
  check_existence "syslog" unless windows?
  check_existence "thread"
  #check_existence "tk" # depend on Tcl/Tk
  #check_existence "tk/tkutil" # depend on Tcl/Tk
  check_existence "Win32API" if windows?
  check_existence "win32ole" if windows?
  check_existence "zlib", "this may be false positive, but should assert because rubygems requires this"
end
