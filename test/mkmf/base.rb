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
    @mkmfobj.instance_eval(*args, &block)
  end

  def config_value(name)
    create_tmpsrc("---config-value=#{name}")
    xpopen(cpp_command('')) do |f|
      f.grep(/^---config-value=(.*)/) {return $1}
    end
    nil
  end
end
