class TestExtLibs < Test::Unit::TestCase
  def self.check_existance(ext, add_msg = nil)
    add_msg = ".  #{add_msg}" if add_msg
    define_method("test_existance_of_#{ext.gsub(%r'/', '_')}") do
      assert_nothing_raised("extension library `#{ext}' is not found#{add_msg}") do
        require ext
      end
    end
  end

  def windows?
    /mswin|mingw/ =~ RUBY_PLATFORM
  end

  check_existance "bigdecimal"
  check_existance "continuation"
  check_existance "coverage"
  check_existance "date"
  #check_existance "dbm" # depend on libdbm
  check_existance "digest"
  check_existance "digest/bubblebabble"
  check_existance "digest/md5"
  check_existance "digest/rmd160"
  check_existance "digest/sha1"
  check_existance "digest/sha2"
  check_existance "etc"
  check_existance "fcntl"
  check_existance "fiber"
  check_existance "fiddle"
  #check_existance "gdbm" # depend on libgdbm
  check_existance "io/console"
  check_existance "io/nonblock"
  check_existance "io/wait"
  check_existance "json"
  #check_existance "mathn/complex" # break the world
  #check_existance "mathn/rational" # break the world
  check_existance "nkf"
  check_existance "objspace"
  check_existance "openssl", "this may be false positive, but should assert because rubygems requires this"
  check_existance "pathname"
  check_existance "psych"
  check_existance "pty" unless windows?
  check_existance "racc/cparse"
  check_existance "rbconfig/sizeof"
  #check_existance "readline" # depend on libreadline
  check_existance "ripper"
  check_existance "sdbm"
  check_existance "socket"
  check_existance "stringio"
  check_existance "strscan"
  check_existance "syslog" unless windows?
  check_existance "thread"
  #check_existance "tk" # depend on Tcl/Tk
  #check_existance "tk/tkutil" # depend on Tcl/Tk
  check_existance "Win32API" if windows?
  check_existance "win32ole" if windows?
  check_existance "zlib", "this may be false positive, but should assert because rubygems requires this"
end
