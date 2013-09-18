require 'shell'
require 'tmpdir'
require_relative '../ruby/envutil'

class TestShell < Test::Unit::TestCase
end
class TestShell::CommandProcessor < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir("test_shell")
    @shell = Shell.new
    @shell.system_path = [@tmpdir]
  end

  def catch_command_start(tc = Object.new)
    @shell.process_controller.singleton_class.class_eval do
      define_method(:add_schedule) {|cmd| throw tc, cmd}
    end
    tc
  end

  def test_system_external
    ext = RbConfig::CONFIG["EXECUTABLE_EXTS"][/\S+\z/]
    path = File.join(@tmpdir, "foo#{ext}")
    open(path, "w", 0755) {}

    cmd = assert_throw(catch_command_start) {@shell.system("foo")}
    assert_equal(path, cmd.command)
  ensure
    File.unlink(path)
  end

  def test_system_not_found
    bug8918 = '[ruby-core:57235] [Bug #8918]'

    path = File.join(@tmpdir, "foo")
    open(path, "w", 0644) {}

    assert_raise(Shell::Error::CommandNotFound, bug8918) {
      catch(catch_command_start) {@shell.system("foo")}
    }
  ensure
    Process.waitall
    File.unlink(path)
  end
end
