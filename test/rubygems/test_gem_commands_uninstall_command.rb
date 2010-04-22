require_relative 'gemutilities'
require_relative 'gem_installer_test_case'
require 'rubygems/commands/uninstall_command'

class TestGemCommandsUninstallCommand < GemInstallerTestCase

  def setup
    super

    ui = MockGemUi.new
    util_setup_gem ui

    build_rake_in do
      use_ui ui do
        @installer.install
      end
    end

    @cmd = Gem::Commands::UninstallCommand.new
    @cmd.options[:executables] = true
    @executable = File.join(@gemhome, 'bin', 'executable')
  end

  def test_execute_removes_executable
    if win_platform?
      assert_equal true, File.exist?(@executable)
    else
      assert_equal true, File.symlink?(@executable)
    end

    # Evil hack to prevent false removal success
    FileUtils.rm_f @executable
    File.open(@executable, "wb+") {|f| f.puts "binary"}

    @cmd.options[:args] = Array(@spec.name)
    use_ui @ui do
      @cmd.execute
    end

    output = @ui.output.split "\n"
    assert_match(/Removing executable/, output.shift)
    assert_match(/Successfully uninstalled/, output.shift)
    assert_equal false, File.exist?(@executable)
    assert_nil output.shift, "UI output should have contained only two lines"
  end

  def test_execute_not_installed
    @cmd.options[:args] = ["foo"]
    e = assert_raises Gem::InstallError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match(/\Acannot uninstall, check `gem list -d foo`$/, e.message)
    output = @ui.output.split "\n"
    assert_empty output, "UI output should be empty after an uninstall error"
  end

  def test_execute_prerelease
    @spec = quick_gem "pre", "2.b"
    @gem = File.join @tempdir, @spec.file_name
    FileUtils.touch @gem

    util_setup_gem

    build_rake_in do
      use_ui @ui do
        @installer.install
      end
    end

    @cmd.options[:args] = ["pre"]

    use_ui @ui do
      @cmd.execute
    end

    output = @ui.output
    assert_match(/Successfully uninstalled/, output)
  end
end

