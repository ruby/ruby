require 'test/unit'
require 'mkmf'
require 'tmpdir'

$extout = '$(topdir)/'+RbConfig::CONFIG["EXTOUT"]
RbConfig::CONFIG['topdir'] = CONFIG['topdir'] = File.expand_path(CONFIG['topdir'])
RbConfig::CONFIG["extout"] = CONFIG["extout"] = $extout
$INCFLAGS << " -I."
$extout_prefix = "$(extout)$(target_prefix)/"

class TestMkmf < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir
    @curdir = Dir.pwd
    @mkmfobj = Object.new
    Dir.chdir(@tmpdir)
    class << (@output = "")
      def flush; end
      def reopen(*) end
      alias write <<
    end
    $stdout = @output
  end

  def teardown
    $stdout = STDOUT
    Dir.chdir(@curdir)
    FileUtils.rm_rf(@tmpdir)
  end

  def mkmf(*args, &block)
    @mkmfobj.instance_eval(*args, &block)
  end

  def default_test
  end
end
