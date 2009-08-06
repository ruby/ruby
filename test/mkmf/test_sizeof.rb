require 'test/unit'
require 'mkmf'
require 'tmpdir'

$extout = '$(topdir)/'+RbConfig::CONFIG["EXTOUT"]
RbConfig::CONFIG['topdir'] = CONFIG['topdir'] = File.expand_path(CONFIG['topdir'])
RbConfig::CONFIG["extout"] = CONFIG["extout"] = $extout
$extout_prefix = "$(extout)$(target_prefix)/"

class TestMkmf < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir
    @mkmfobj = Object.new
  end
  def mkmf(*args, &block)
    @mkmfobj.instance_eval(*args, &block)
  end

  def test_sizeof
    Dir.chdir(@tmpdir) do
      open("confdefs.h", "w") {|f|
        f.puts "typedef struct {char x;} test1_t;"
      }
      mkmf {check_sizeof("test1_t", "confdefs.h")} rescue puts File.read("mkmf.log")
    end
  end
end
