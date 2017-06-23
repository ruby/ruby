# frozen_string_literal: false
require 'shell'
require 'tmpdir'

class TestShell < Test::Unit::TestCase
end
class TestShell::CommandProcessor < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir("test_shell")
    @shell = Shell.new
    @shell.system_path = [@tmpdir]
  end

  def teardown
    Dir.rmdir(@tmpdir)
  end

  def catch_command_start(tc = Object.new)
    @shell.process_controller.singleton_class.class_eval do
      define_method(:add_schedule) {|cmd| throw tc, cmd}
    end
    tc
  end

  def exeext
    RbConfig::CONFIG["EXECUTABLE_EXTS"][/\S+\z/]
  end

  def test_system_external
    name = "foo#{exeext}"
    path = File.join(@tmpdir, name)
    open(path, "w", 0755) {}

    cmd = assert_throw(catch_command_start) {@shell.system(name)}
    assert_equal(path, cmd.command)
  ensure
    File.unlink(path)
  end

  def test_system_not_found
    bug8918 = '[ruby-core:57235] [Bug #8918]'

    name = "foo"
    path = File.join(@tmpdir, name)
    open(path, "w", 0644) {}

    assert_raise(Shell::Error::CommandNotFound, bug8918) {
      catch(catch_command_start) {@shell.system(name)}
    }
  ensure
    Process.waitall
    File.unlink(path)
  end

  def test_system_directory
    bug8918 = '[ruby-core:57235] [Bug #8918]'

    name = "foo#{exeext}"
    path = File.join(@tmpdir, name)
    Dir.mkdir(path)

    assert_raise(Shell::Error::CommandNotFound, bug8918) {
      catch(catch_command_start) {@shell.system(name)}
    }
  ensure
    Process.waitall
    Dir.rmdir(path)
  end

  def test_option_type
    name = 'foo.cmd'
    path = File.join(@tmpdir, name)

    open(path, 'w', 0755) {}
    assert_raise(TypeError) {
      catch(catch_command_start) {@shell.system(name, 42)}
    }
  ensure
    Process.waitall
    File.unlink(path)
  end
end
