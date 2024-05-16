# frozen_string_literal: true

require_relative "installer_test_case"
require "rubygems/commands/uninstall_command"

class TestGemCommandsUninstallCommand < Gem::InstallerTestCase
  def setup
    super
    @cmd = Gem::Commands::UninstallCommand.new
    @executable = File.join(@gemhome, "bin", "executable")
  end

  def test_execute_all_named
    initial_install

    util_make_gems

    default = new_default_spec "default", "1"
    install_default_gems default

    gemhome2 = "#{@gemhome}2"

    a_4, = util_gem "a", 4
    install_gem a_4, install_dir: gemhome2

    assert_gems_presence "a-1", "a-4", "b-2", "default-1", dirs: [@gemhome, gemhome2]

    @cmd.options[:all] = true
    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal %w[a-4 a_evil-9 b-2 c-1.2 default-1 dep_x-1 pl-1-x86-linux x-1],
                 Gem::Specification.all_names.sort
  end

  def test_execute_all_named_default_single
    z_1 = new_default_spec "z", "1"
    install_default_gems z_1

    assert_includes Gem::Specification.all_names, "z-1"

    @cmd.options[:all] = true
    @cmd.options[:args] = %w[z]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal %w[z-1], Gem::Specification.all_names.sort

    output = @ui.output.split "\n"

    assert_equal "Gem z-1 cannot be uninstalled because it is a default gem", output.shift
  end

  def test_execute_all_named_default_multiple
    z_1 = new_default_spec "z", "1"
    install_default_gems z_1

    z_2, = util_gem "z", 2
    install_gem z_2

    assert_includes Gem::Specification.all_names, "z-1"
    assert_includes Gem::Specification.all_names, "z-2"

    @cmd.options[:all] = true
    @cmd.options[:args] = %w[z]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal %w[z-1], Gem::Specification.all_names.sort

    output = @ui.output.split "\n"

    assert_equal "Gem z-1 cannot be uninstalled because it is a default gem", output.shift
    assert_equal "Successfully uninstalled z-2", output.shift
  end

  def test_execute_dependency_order
    initial_install

    c = quick_gem "c" do |spec|
      spec.add_dependency "a"
    end

    util_build_gem c
    installer = util_installer c, @gemhome

    use_ui @ui do
      installer.install
    end

    ui = Gem::MockGemUi.new

    @cmd.options[:args] = %w[a c]
    @cmd.options[:executables] = true

    use_ui ui do
      @cmd.execute
    end

    output = ui.output.split "\n"

    assert_equal "Successfully uninstalled c-2", output.shift
    assert_equal "Removing executable",          output.shift
    assert_equal "Successfully uninstalled a-2", output.shift
  end

  def test_execute_removes_executable
    initial_install

    if Gem.win_platform?
      assert File.exist?(@executable)
    else
      assert File.symlink?(@executable)
    end

    # Evil hack to prevent false removal success
    FileUtils.rm_f @executable

    File.open @executable, "wb+" do |f|
      f.puts "binary"
    end

    @cmd.options[:executables] = true
    @cmd.options[:args] = [@spec.name]
    use_ui @ui do
      @cmd.execute
    end

    output = @ui.output.split "\n"
    assert_match(/Removing executable/, output.shift)
    assert_match(/Successfully uninstalled/, output.shift)
    assert_equal false, File.exist?(@executable)
    assert_nil output.shift, "UI output should have contained only two lines"
  end

  def test_execute_removes_formatted_executable
    installer = setup_base_installer

    FileUtils.rm_f @executable # Wish this didn't happen in #setup

    Gem::Installer.exec_format = "foo-%s-bar"

    installer.format_executable = true
    installer.install

    formatted_executable = File.join @gemhome, "bin", "foo-executable-bar"
    assert_equal true, File.exist?(formatted_executable)

    @cmd.options[:executables] = true
    @cmd.options[:format_executable] = true
    @cmd.execute

    assert_equal false, File.exist?(formatted_executable)
  rescue StandardError
    Gem::Installer.exec_format = nil
  end

  def test_execute_prerelease
    @spec = util_spec "pre", "2.b"
    @gem = File.join @tempdir, @spec.file_name
    FileUtils.touch @gem

    installer = util_setup_gem

    build_rake_in do
      use_ui @ui do
        installer.install
      end
    end

    @cmd.options[:executables] = true
    @cmd.options[:args] = ["pre"]

    use_ui @ui do
      @cmd.execute
    end

    output = @ui.output
    assert_match(/Successfully uninstalled/, output)
  end

  def test_execute_with_version_leaves_non_matching_versions
    initial_install

    ui = Gem::MockGemUi.new

    util_make_gems

    assert_equal 3, Gem::Specification.find_all_by_name("a").length

    @cmd.options[:version] = "1"
    @cmd.options[:force] = true
    @cmd.options[:args] = ["a"]

    use_ui ui do
      @cmd.execute
    end

    assert_equal 2, Gem::Specification.find_all_by_name("a").length

    assert File.exist? File.join(@gemhome, "bin", "executable")
  end

  def test_execute_with_version_specified_as_colon
    initial_install

    ui = Gem::MockGemUi.new "y\n"

    util_make_gems

    assert_equal 3, Gem::Specification.find_all_by_name("a").length

    @cmd.options[:force] = true
    @cmd.options[:args] = ["a:1"]

    use_ui ui do
      @cmd.execute
    end

    assert_equal 2, Gem::Specification.find_all_by_name("a").length

    assert File.exist? File.join(@gemhome, "bin", "executable")
  end

  def test_execute_with_multiple_version_specified_as_colon
    initial_install

    ui = Gem::MockGemUi.new "y\n"

    util_make_gems

    assert_equal 3, Gem::Specification.find_all_by_name("a").length

    @cmd.options[:force] = true
    @cmd.options[:args] = ["a:1", "a:2"]

    use_ui ui do
      @cmd.execute
    end

    assert_equal 1, Gem::Specification.find_all_by_name("a").length
    assert_equal Gem::Version.new("3.a"), Gem::Specification.find_by_name("a").version
  end

  def test_uninstall_selection
    ui = Gem::MockGemUi.new "1\n"

    util_make_gems

    list = Gem::Specification.find_all_by_name "a"

    @cmd.options[:args] = ["a"]

    use_ui ui do
      @cmd.execute
    end

    updated_list = Gem::Specification.find_all_by_name("a")
    assert_equal list.length - 1, updated_list.length

    assert_match " 1. a-1",          ui.output
    assert_match " 2. a-2",          ui.output
    assert_match " 3. a-3.a",        ui.output
    assert_match " 4. All versions", ui.output
    assert_match "uninstalled a-1",  ui.output
  end

  def test_uninstall_selection_multiple_gems
    ui = Gem::MockGemUi.new "1\n"

    util_make_gems

    a_list = Gem::Specification.find_all_by_name("a")
    b_list = Gem::Specification.find_all_by_name("b")
    list   = a_list + b_list

    @cmd.options[:args] = ["a", "b"]

    use_ui ui do
      @cmd.execute
    end

    updated_a_list = Gem::Specification.find_all_by_name("a")
    updated_b_list = Gem::Specification.find_all_by_name("b")
    updated_list   = updated_a_list + updated_b_list

    assert_equal list.length - 2, updated_list.length

    out = ui.output.split("\n")
    assert_match "uninstalled b-2",          out.shift
    assert_match "",                         out.shift
    assert_match "Select gem to uninstall:", out.shift
    assert_match " 1. a-1",                  out.shift
    assert_match " 2. a-2",                  out.shift
    assert_match " 3. a-3.a",                out.shift
    assert_match " 4. All versions",         out.shift
    assert_match "uninstalled a-1",          out.shift
    assert_empty                             out
  end

  def test_execute_with_force_and_without_version_uninstalls_everything
    initial_install

    ui = Gem::MockGemUi.new "y\n"

    a_1, = util_gem "a", 1
    install_gem a_1

    a_3a, = util_gem "a", "3.a"
    install_gem a_3a

    assert_equal 3, Gem::Specification.find_all_by_name("a").length

    @cmd.options[:force] = true
    @cmd.options[:args] = ["a"]

    use_ui ui do
      @cmd.execute
    end

    assert_empty Gem::Specification.find_all_by_name("a")
    assert_match "Removing executable", ui.output
    refute File.exist? @executable
  end

  def test_execute_with_force_ignores_dependencies
    initial_install

    ui = Gem::MockGemUi.new

    util_make_gems

    assert Gem::Specification.find_all_by_name("dep_x").length > 0
    assert Gem::Specification.find_all_by_name("x").length > 0

    @cmd.options[:force] = true
    @cmd.options[:args] = ["x"]

    use_ui ui do
      @cmd.execute
    end

    assert Gem::Specification.find_all_by_name("dep_x").length > 0
    assert Gem::Specification.find_all_by_name("x").length.zero?
  end

  def test_execute_all
    util_make_gems

    default = new_default_spec "default", "1"
    install_default_gems default

    gemhome2 = "#{@gemhome}2"

    a_4, = util_gem "a", 4
    install_gem a_4

    assert_gems_presence "a-1", "a-4", "default-1", dirs: [@gemhome, gemhome2]

    @cmd.options[:all] = true
    @cmd.options[:args] = []

    use_ui @ui do
      @cmd.execute
    end

    assert_equal %w[default-1], Gem::Specification.all_names.sort
    assert_equal "INFO:  Uninstalled all gems in #{@gemhome}", @ui.output.split("\n").last
  end

  def test_execute_outside_gem_home
    ui = Gem::MockGemUi.new "y\n"

    gemhome2 = "#{@gemhome}2"

    a_4, = util_gem "a", 4
    install_gem a_4, install_dir: gemhome2

    assert_gems_presence "a-4", dirs: [@gemhome, gemhome2]

    @cmd.options[:args] = ["a:4"]

    e = assert_raise Gem::InstallError do
      use_ui ui do
        @cmd.execute
      end
    end

    assert_includes e.message, "a is not installed in GEM_HOME"
  end

  def test_execute_outside_gem_home_when_install_dir_given
    gemhome2 = "#{@gemhome}2"

    a_4, = util_gem "a", 4
    install_gem a_4, install_dir: gemhome2

    assert_gems_presence "a-4", dirs: [@gemhome, gemhome2]

    Gem::Specification.dirs = [@gemhome]

    @cmd.options[:install_dir] = gemhome2
    @cmd.options[:args] = ["a:4"]

    @cmd.execute

    Gem::Specification.dirs = [gemhome2]

    refute_includes Gem::Specification.all_names.sort, "a-4"
  end

  def test_handle_options
    @cmd.handle_options %w[]

    assert_equal false,                    @cmd.options[:check_dev]
    assert_nil                             @cmd.options[:install_dir]
    assert_equal true,                     @cmd.options[:user_install]
    assert_equal Gem::Requirement.default, @cmd.options[:version]
    assert_equal false,                    @cmd.options[:vendor]
  end

  def test_handle_options_vendor
    vendordir(File.join(@tempdir, "vendor")) do
      use_ui @ui do
        @cmd.handle_options %w[--vendor]
      end

      assert @cmd.options[:vendor]
      assert_equal Gem.vendor_dir, @cmd.options[:install_dir]

      assert_empty @ui.output

      expected = <<-EXPECTED
WARNING:  Use your OS package manager to uninstall vendor gems
      EXPECTED

      assert_match expected, @ui.error
    end
  end

  def test_execute_two_version
    @cmd.options[:args] = %w[a b]
    @cmd.options[:version] = Gem::Requirement.new("> 1")

    use_ui @ui do
      e = assert_raise Gem::MockGemUi::TermError do
        @cmd.execute
      end

      assert_equal 1, e.exit_code
    end

    msg = "ERROR:  Can't use --version with multiple gems. You can specify multiple gems with" \
      " version requirements using `gem uninstall 'my_gem:1.0.0' 'my_other_gem:~>2.0.0'`"

    assert_empty @ui.output
    assert_equal msg, @ui.error.lines.last.chomp
  end

  def test_handle_options_vendor_missing
    vendordir(nil) do
      e = assert_raise Gem::OptionParser::InvalidOption do
        @cmd.handle_options %w[--vendor]
      end

      assert_equal "invalid option: --vendor your platform is not supported",
                   e.message

      refute @cmd.options[:vendor]
      refute @cmd.options[:install_dir]
    end
  end

  def test_execute_with_gem_not_installed
    @cmd.options[:args] = ["d"]

    use_ui ui do
      @cmd.execute
    end

    output = ui.output.split "\n"

    assert_equal output.first, "Gem 'd' is not installed"
  end

  def test_execute_with_gem_uninstall_error
    initial_install

    util_make_gems

    @cmd.options[:args] = %w[a]

    uninstall_exception = lambda do |_a|
      ex = Gem::UninstallError.new
      ex.spec = @spec

      raise ex
    end

    e = nil
    @cmd.stub :uninstall, uninstall_exception do
      use_ui @ui do
        e = assert_raise Gem::MockGemUi::TermError do
          @cmd.execute
        end
      end

      assert_equal 1, e.exit_code
    end

    assert_empty @ui.output
    assert_match(/Error: unable to successfully uninstall '#{@spec.name}'/, @ui.error)
  end

  private

  def initial_install
    installer = setup_base_installer
    common_installer_setup

    build_rake_in do
      use_ui @ui do
        installer.install
      end
    end
  end

  def assert_gems_presence(*gems, dirs:)
    Gem::Specification.dirs = dirs

    gems.each do |full_name|
      assert_includes Gem::Specification.all_names, full_name
    end
  end
end
