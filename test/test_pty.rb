require 'test/unit'
require_relative 'ruby/envutil'
require 'shellwords'

begin
  require 'pty'
rescue LoadError
end

class TestPTY < Test::Unit::TestCase
  RUBY = EnvUtil.rubybin

  def test_spawn_without_block
    r, w, pid = PTY.spawn(RUBY, '-e', 'puts "a"')
    assert_equal("a\r\n", r.gets)
    assert_raise(Errno::EIO) { r.gets }
  ensure
    Process.wait pid if pid
  end

  def test_spawn_with_block
    PTY.spawn(RUBY, '-e', 'puts "b"') {|r,w,pid|
      assert_equal("b\r\n", r.gets)
      Process.wait(pid)
      assert_raise(Errno::EIO) { r.gets }
    }
  end

  def test_commandline
    commandline = Shellwords.join([RUBY, '-e', 'puts "foo"'])
    PTY.spawn(commandline) {|r,w,pid|
      assert_equal("foo\r\n", r.gets)
      Process.wait(pid)
      assert_raise(Errno::EIO) { r.gets }
    }
  end

  def test_argv0
    PTY.spawn([RUBY, "argv0"], '-e', 'puts "bar"') {|r,w,pid|
      assert_equal("bar\r\n", r.gets)
      Process.wait(pid)
      assert_raise(Errno::EIO) { r.gets }
    }
  end
end if defined? PTY

