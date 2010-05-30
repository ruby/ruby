require 'test/unit'
require 'tempfile'
require 'timeout'
require_relative 'envutil'

class TestBeginEndBlock < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))

  def q(content)
    "\"#{content}\""
  end

  def test_beginendblock
    ruby = EnvUtil.rubybin
    target = File.join(DIR, 'beginmainend.rb')
    result = IO.popen([ruby, target]){|io|io.read}
    assert_equal(%w(b1 b2-1 b2 main b3-1 b3 b4 e1 e4 e3 e2 e4-2 e4-1 e1-1 e4-1-1), result.split)

    input = Tempfile.new(self.class.name)
    inputpath = input.path
    input.close
    result = IO.popen([ruby, "-n", "-eBEGIN{p :begin}", "-eEND{p :end}", inputpath]){|io|io.read}
    assert_equal(%w(:begin), result.split)
    result = IO.popen([ruby, "-p", "-eBEGIN{p :begin}", "-eEND{p :end}", inputpath]){|io|io.read}
    assert_equal(%w(:begin), result.split)
    input.open
    input.puts "foo\nbar"
    input.close
    result = IO.popen([ruby, "-n", "-eBEGIN{p :begin}", "-eEND{p :end}", inputpath]){|io|io.read}
    assert_equal(%w(:begin :end), result.split)
    result = IO.popen([ruby, "-p", "-eBEGIN{p :begin}", "-eEND{p :end}", inputpath]){|io|io.read}
    assert_equal(%w(:begin foo bar :end), result.split)
  end

  def test_begininmethod
    assert_raise(SyntaxError) do
      eval("def foo; BEGIN {}; end")
    end

    assert_raise(SyntaxError) do
      eval('eval("def foo; BEGIN {}; end")')
    end
  end

  def test_begininclass
    assert_raise(SyntaxError) do
      eval("class TestBeginEndBlock; BEGIN {}; end")
    end
  end

  def test_endblockwarn
    ruby = EnvUtil.rubybin
    # Use Tempfile to create temporary file path.
    launcher = Tempfile.new(self.class.name)
    errout = Tempfile.new(self.class.name)

    launcher << <<EOF
# -*- coding: #{ruby.encoding.name} -*-
errout = ARGV.shift
STDERR.reopen(File.open(errout, "w"))
STDERR.sync = true
Dir.chdir(#{q(DIR)})
system("#{ruby}", "endblockwarn_rb")
EOF
    launcher.close
    launcherpath = launcher.path
    errout.close
    erroutpath = errout.path
    system(ruby, launcherpath, erroutpath)
    expected = <<EOW
endblockwarn_rb:2: warning: END in method; use at_exit
(eval):2: warning: END in method; use at_exit
EOW
    assert_equal(expected, File.read(erroutpath))
    # expecting Tempfile to unlink launcher and errout file.
  end

  def test_raise_in_at_exit
    ruby = EnvUtil.rubybin
    out = IO.popen([ruby, '-e', 'STDERR.reopen(STDOUT)',
                     '-e', 'at_exit{raise %[SomethingBad]}',
                     '-e', 'raise %[SomethingElse]']) {|f|
      f.read
    }
    assert_match(/SomethingBad/, out, "[ruby-core:9675]")
    assert_match(/SomethingElse/, out, "[ruby-core:9675]")
  end

  def test_should_propagate_exit_code
    ruby = EnvUtil.rubybin
    assert_equal false, system(ruby, '-e', 'at_exit{exit 2}')
    assert_equal 2, $?.exitstatus
    assert_nil $?.termsig
  end

  def test_should_propagate_signaled
    ruby = EnvUtil.rubybin
    out = IO.popen(
      [ruby,
       '-e', 'STDERR.reopen(STDOUT)',
       '-e', 'at_exit{Process.kill(:INT, $$); sleep 5 }']) {|f|
      timeout(10) {
        f.read
      }
    }
    assert_match(/Interrupt$/, out)
    Process.kill(0, 0) rescue return # check if signal works
    assert_nil $?.exitstatus
    assert_equal Signal.list["INT"], $?.termsig
  end
end
