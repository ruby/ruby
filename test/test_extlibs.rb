# frozen_string_literal: false
require "envutil"
require "shellwords"

class TestExtLibs < Test::Unit::TestCase
  @extdir = $".grep(/\/rbconfig\.rb\z/) {break "#$`/ext"}

  def self.check_existence(ext, add_msg = nil)
    return if @excluded.any? {|i| File.fnmatch?(i, ext, File::FNM_CASEFOLD)}
    add_msg = ".  #{add_msg}" if add_msg
    log = "#{@extdir}/#{ext}/mkmf.log"
    define_method("test_existence_of_#{ext}") do
      assert_separately([], <<-"end;", ignore_stderr: true) # do
        log = #{log.dump}
        msg = proc {
          "extension library `#{ext}' is not found#{add_msg}\n" <<
            (File.exist?(log) ? File.binread(log) : "\#{log} not found")
        }
        assert_nothing_raised(msg) do
          require "#{ext}"
        end
      end;
    end
  end

  def windows?
    /mswin|mingw/ =~ RUBY_PLATFORM
  end

  excluded = [RbConfig::CONFIG, ENV].map do |conf|
    if args = conf['configure_args']
      args.shellsplit.grep(/\A--without-ext=/) {$'.split(/,/)}
    end
  end.flatten.compact
  excluded << '+' if excluded.empty?
  if windows?
    excluded.map! {|i| i == '+' ? ['pty', 'syslog'] : i}
    excluded.flatten!
  else
    excluded.map! {|i| i == '+' ? '*win32*' : i}
  end
  @excluded = excluded

  check_existence "bigdecimal"
  check_existence "continuation"
  check_existence "coverage"
  check_existence "date"
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
  check_existence "io/console"
  check_existence "io/nonblock"
  check_existence "io/wait"
  check_existence "json"
  check_existence "nkf"
  check_existence "objspace"
  check_existence "openssl", "this may be false positive, but should assert because rubygems requires this"
  check_existence "pathname"
  check_existence "psych"
  check_existence "pty"
  check_existence "racc/cparse"
  check_existence "rbconfig/sizeof"
  #check_existence "readline" # depend on libreadline
  check_existence "ripper"
  check_existence "socket"
  check_existence "stringio"
  check_existence "strscan"
  check_existence "syslog"
  check_existence "thread"
  check_existence "win32ole"
  check_existence "zlib", "this may be false positive, but should assert because rubygems requires this"
end
