require 'test/unit'
require 'mkmf'
require 'tmpdir'
require_relative '../ruby/envutil'

$extout = '$(topdir)/'+RbConfig::CONFIG["EXTOUT"]
RbConfig::CONFIG['topdir'] = CONFIG['topdir'] = File.expand_path(CONFIG['topdir'])
RbConfig::CONFIG["extout"] = CONFIG["extout"] = $extout
$INCFLAGS << " -I."
$extout_prefix = "$(extout)$(target_prefix)/"

class TestMkmf < Test::Unit::TestCase
  MKMFLOG = proc {File.read("mkmf.log") rescue ""}
  class << MKMFLOG
    alias to_s call
  end

  class Capture
    attr_accessor :origin
    def initialize
      @buffer = ""
      @filter = nil
      @out = true
      @origin = nil
    end
    def clear
      @buffer.clear
    end
    def flush
      STDOUT.print @filter ? @filter.call(@buffer) : @buffer
      clear
    end
    def reopen(io)
      case io
      when Capture
        initialize_copy(io)
      when File
        @out = false
        @origin.reopen(io) if @origin
      when IO
        @out = true
        @origin.reopen(io) if @origin
      else
        @out = false
      end
    end
    def filter(&block)
      @filter = block
    end
    def write(s)
      @buffer << s if @out
    end
  end
end

module TestMkmf::Base
  attr_reader :stdout

  def mkmflog(msg)
    log = proc {MKMFLOG[] << msg}
    class << log
      alias to_s call
    end
    log
  end

  def setup
    @rbconfig = rbconfig0 = RbConfig::CONFIG
    @mkconfig = mkconfig0 = RbConfig::MAKEFILE_CONFIG
    rbconfig = {
      "hdrdir" => $hdrdir,
      "srcdir" => $srcdir,
      "topdir" => $topdir,
    }
    mkconfig = {
      "hdrdir" => "$(top_srcdir)/include",
      "srcdir" => "$(top_srcdir)",
      "topdir" => $topdir,
    }
    rbconfig0.each_pair {|key, val| rbconfig[key] ||= val.dup}
    mkconfig0.each_pair {|key, val| mkconfig[key] ||= val.dup}
    RbConfig.module_eval {
      remove_const(:CONFIG)
      const_set(:CONFIG, rbconfig)
      remove_const(:MAKEFILE_CONFIG)
      const_set(:MAKEFILE_CONFIG, mkconfig)
    }
    MakeMakefile.class_eval {
      remove_const(:CONFIG)
      const_set(:CONFIG, mkconfig)
    }
    @tmpdir = Dir.mktmpdir
    @curdir = Dir.pwd
    @mkmfobj = Object.new
    @stdout = TestMkmf::Capture.new
    Dir.chdir(@tmpdir)
    @quiet, Logging.quiet = Logging.quiet, true
    init_mkmf
    $INCFLAGS[0, 0] = "-I. "
  end

  def teardown
    rbconfig0 = @rbconfig
    mkconfig0 = @mkconfig
    RbConfig.module_eval {
      remove_const(:CONFIG)
      const_set(:CONFIG, rbconfig0)
      remove_const(:MAKEFILE_CONFIG)
      const_set(:MAKEFILE_CONFIG, mkconfig0)
    }
    MakeMakefile.class_eval {
      remove_const(:CONFIG)
      const_set(:CONFIG, mkconfig0)
    }
    Logging.quiet = @quiet
    Logging.log_close
    FileUtils.rm_f("mkmf.log")
    Dir.chdir(@curdir)
    FileUtils.rm_rf(@tmpdir)
  end

  def mkmf(*args, &block)
    @stdout.clear
    stdout, @stdout.origin, $stdout = @stdout.origin, $stdout, @stdout
    @mkmfobj.instance_eval(*args, &block)
  ensure
    $stdout, @stdout.origin = @stdout.origin, stdout
  end

  def config_value(name)
    create_tmpsrc("---config-value=#{name}")
    xpopen(cpp_command('')) do |f|
      f.grep(/^---config-value=(.*)/) {return $1}
    end
    nil
  end
end

class TestMkmf
  include TestMkmf::Base

  def assert_separately(args, src, *rest)
    super(args + ["-r#{__FILE__}"], "extend TestMkmf::Base; setup\n#{src}", *rest)
  end
end
