require 'test/unit'
require 'tempfile'
$:.replace([File.dirname(File.expand_path(__FILE__))] | $:)
require 'envutil'

class TestBeginEndBlock < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))

  def q(content)
    "\"#{content}\""
  end

  def test_beginendblock
    ruby = EnvUtil.rubybin
    target = File.join(DIR, 'beginmainend.rb')
    io = IO.popen("#{q(ruby)} #{q(target)}")
    assert_equal(%w(b1 b2-1 b2 main b3-1 b3 b4 e1 e4 e3 e2 e4-2 e4-1 e1-1 e4-1-1), io.read.split)
    io.close
  end

  def test_begininmethod
    assert_raises(SyntaxError) do
      eval("def foo; BEGIN {}; end")
    end

    assert_raises(SyntaxError) do
      eval('eval("def foo; BEGIN {}; end")')
    end
  end

  def test_endblockwarn
    ruby = EnvUtil.rubybin
    # Use Tempfile to create temporary file path.
    launcher = Tempfile.new(self.class.name)
    errout = Tempfile.new(self.class.name)

    launcher << <<EOF
errout = ARGV.shift
STDERR.reopen(File.open(errout, "w"))
STDERR.sync = true
Dir.chdir(#{q(DIR)})
cmd = "\\"#{ruby}\\" \\"endblockwarn.rb\\""
system(cmd)
EOF
    launcher.close
    launcherpath = launcher.path
    errout.close
    erroutpath = errout.path
    system("#{q(ruby)} #{q(launcherpath)} #{q(erroutpath)}")
    expected = <<EOW
endblockwarn.rb:2: warning: END in method; use at_exit
(eval):2: warning: END in method; use at_exit
EOW
    assert_equal(expected, File.read(erroutpath))
    # expecting Tempfile to unlink launcher and errout file.
  end
end
