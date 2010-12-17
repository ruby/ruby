require 'test/unit'
require 'mkmf'
require 'tmpdir'

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
    def initialize
      @buffer = ""
      @filter = nil
      @out = true
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
      when IO
        @out = true
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

  attr_reader :stdout

  def mkmflog(msg)
    log = proc {MKMFLOG[] << msg}
    class << log
      alias to_s call
    end
    log
  end

  def setup
    @tmpdir = Dir.mktmpdir
    @curdir = Dir.pwd
    @mkmfobj = Object.new
    @stdout = Capture.new
    Dir.chdir(@tmpdir)
    @quiet, Logging.quiet = Logging.quiet, true
  end

  def teardown
    Logging.quiet = @quiet
    Logging.log_close
    Dir.chdir(@curdir)
    FileUtils.rm_rf(@tmpdir)
  end

  def mkmf(*args, &block)
    @stdout.clear
    stdout, $stdout = $stdout, @stdout
    @mkmfobj.instance_eval(*args, &block)
  ensure
    $stdout = stdout
  end

  def config_value(name)
    create_tmpsrc("---config-value=#{name}")
    xpopen(cpp_command('')) do |f|
      f.grep(/^---config-value=(.*)/) {return $1}
    end
    nil
  end
end
