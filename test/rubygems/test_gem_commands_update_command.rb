# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/update_command"

class TestGemCommandsUpdateCommand < Gem::TestCase
  def setup
    super
    common_installer_setup

    @cmd = Gem::Commands::UpdateCommand.new

    @cmd.options[:document] = []

    @specs = spec_fetcher do |fetcher|
      fetcher.download "a", 1
      fetcher.download "a", 2
      fetcher.download "a", "3.a"
    end

    @a1_path  = @specs["a-1"].cache_file
    @a2_path  = @specs["a-1"].cache_file
    @a3a_path = @specs["a-3.a"].cache_file
  end

  def test_execute
    spec_fetcher do |fetcher|
      fetcher.download "a", 2
      fetcher.spec "a", 1
    end

    @cmd.options[:args] = []

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating a", out.shift
    assert_equal "Gems updated: a", out.shift
    assert_empty out
  end

  def test_execute_multiple
    spec_fetcher do |fetcher|
      fetcher.download "a",  2
      fetcher.download "ab", 2

      fetcher.spec "a",  1
      fetcher.spec "ab", 1
    end

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating a", out.shift
    assert_equal "Gems updated: a", out.shift
    assert_empty out
  end

  def test_execute_system
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", 9 do |s|
        s.files = %w[setup.rb]
      end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = true

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Installing RubyGems 9", out.shift
    assert_equal "RubyGems system software updated", out.shift

    assert_empty out
  end

  def test_execute_system_at_latest
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", Gem::VERSION do |s|
        s.files = %w[setup.rb]
      end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = true

    assert_raise Gem::MockGemUi::SystemExitException do
      use_ui @ui do
        @cmd.execute
      end
    end

    out = @ui.output.split "\n"
    assert_equal "Latest version already installed. Done.", out.shift
    assert_empty out
  end

  def test_execute_system_when_latest_does_not_support_your_ruby
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", 9 do |s|
        s.files = %w[setup.rb]
        s.required_ruby_version = "> 9"
      end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = true

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_empty out

    err = @ui.error.split "\n"
    assert_equal "ERROR:  Error installing rubygems-update:", err.shift
    assert_equal "\trubygems-update-9 requires Ruby version > 9. The current ruby version is #{Gem.ruby_version}.", err.shift
    assert_empty err
  end

  def test_execute_system_when_latest_does_not_support_your_ruby_but_previous_one_does
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", 9 do |s|
        s.files = %w[setup.rb]
        s.required_ruby_version = "> 9"
      end

      fetcher.download "rubygems-update", 8 do |s|
        s.files = %w[setup.rb]
      end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = true

    use_ui @ui do
      @cmd.execute
    end

    err = @ui.error.split "\n"
    assert_empty err

    out = @ui.output.split "\n"
    assert_equal "Installing RubyGems 8", out.shift
    assert_equal "RubyGems system software updated", out.shift
    assert_empty out
  end

  def test_execute_system_multiple
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", 8 do |s|
        s.files = %w[setup.rb]
      end

      fetcher.download "rubygems-update", 9 do |s|
        s.files = %w[setup.rb]
      end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = true

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Installing RubyGems 9", out.shift
    assert_equal "RubyGems system software updated", out.shift

    assert_empty out
  end

  def test_execute_system_update_installed
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", 8 do |s|
        s.files = %w[setup.rb]
      end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = true

    @cmd.execute

    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", 9 do |s|
        s.files = %w[setup.rb]
      end
    end

    @cmd = Gem::Commands::UpdateCommand.new
    @cmd.options[:args]          = []
    @cmd.options[:system]        = true

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Installing RubyGems 9", out.shift
    assert_equal "RubyGems system software updated", out.shift

    assert_empty out
  end

  def test_execute_system_update_installed_in_non_default_gem_path
    rubygems_update_spec = quick_gem "rubygems-update", 9 do |s|
      write_file File.join(@tempdir, "setup.rb")

      s.files += %w[setup.rb]
    end

    util_setup_spec_fetcher rubygems_update_spec

    rubygems_update_package = Gem::Package.build rubygems_update_spec

    gemhome2 = "#{@gemhome}2"

    Gem::Installer.at(rubygems_update_package, install_dir: gemhome2).install

    Gem.use_paths @gemhome, [gemhome2, @gemhome]

    @cmd.options[:args]          = []
    @cmd.options[:system]        = true

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Installing RubyGems 9", out.shift
    assert_equal "RubyGems system software updated", out.shift

    assert_empty out
  end

  def test_execute_system_specific
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", 8 do |s|
        s.files = %w[setup.rb]
      end

      fetcher.download "rubygems-update", 9 do |s|
        s.files = %w[setup.rb]
      end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = "8"

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Installing RubyGems 8", out.shift
    assert_equal "RubyGems system software updated", out.shift

    assert_empty out
  end

  def test_execute_system_specific_older_than_minimum_supported_rubygems
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", "2.5.1" do |s|
        s.files = %w[setup.rb]
      end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = "2.5.1"

    oldest_version_mod = Module.new do
      def oldest_supported_version
        Gem::Version.new("2.5.2")
      end
      private :oldest_supported_version
    end

    @cmd.extend(oldest_version_mod)

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_empty @ui.output
    assert_equal "ERROR:  rubygems 2.5.1 is not supported on #{RUBY_VERSION}. The oldest version supported by this ruby is 2.5.2\n", @ui.error
  end

  def test_execute_system_specific_older_than_3_2_removes_plugins_dir
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", 3.1 do |s|
        s.files = %w[setup.rb]
      end
    end

    oldest_version_mod = Module.new do
      def oldest_supported_version
        Gem::Version.new("2.5.2")
      end
      private :oldest_supported_version
    end

    @cmd.extend(oldest_version_mod)

    @cmd.options[:args]          = []
    @cmd.options[:system]        = "3.1"

    FileUtils.mkdir_p Gem.plugindir
    write_file File.join(Gem.plugindir, "a_plugin.rb")

    @cmd.execute

    assert_path_not_exist Gem.plugindir, "Plugins folder not removed when updating rubygems to pre-3.2"
  end

  def test_execute_system_specific_newer_than_or_equal_to_3_2_leaves_plugins_dir_alone
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", "3.2.a" do |s|
        s.files = %w[setup.rb]
      end
    end

    oldest_version_mod = Module.new do
      def oldest_supported_version
        Gem::Version.new("2.5.2")
      end
      private :oldest_supported_version
    end

    @cmd.extend(oldest_version_mod)

    @cmd.options[:args]          = []
    @cmd.options[:system]        = "3.2.a"

    FileUtils.mkdir_p Gem.plugindir
    plugin_file = File.join(Gem.plugindir, "a_plugin.rb")
    write_file plugin_file

    @cmd.execute

    assert_path_exist Gem.plugindir, "Plugin folder removed when updating rubygems to post-3.2"
    assert_path_exist plugin_file, "Plugin removed when updating rubygems to post-3.2"
  end

  def test_execute_system_specifically_to_latest_version
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", 8 do |s|
        s.files = %w[setup.rb]
      end

      fetcher.download "rubygems-update", 9 do |s|
        s.files = %w[setup.rb]
      end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = "9"

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Installing RubyGems 9", out.shift
    assert_equal "RubyGems system software updated", out.shift

    assert_empty out
  end

  def test_execute_system_with_gems
    @cmd.options[:args]          = %w[gem]
    @cmd.options[:system]        = true

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_empty @ui.output
    assert_equal "ERROR:  Gem names are not allowed with the --system option\n",
                 @ui.error
  end

  def test_execute_system_with_disabled_update
    old_disable_system_update_message = Gem.disable_system_update_message
    Gem.disable_system_update_message = "Please use package manager instead."

    @cmd.options[:args] = []
    @cmd.options[:system] = true

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_empty @ui.output
    assert_equal "ERROR:  Please use package manager instead.\n", @ui.error
  ensure
    Gem.disable_system_update_message = old_disable_system_update_message
  end

  # The other style of `gem update --system` tests don't actually run
  # setup.rb, so we just check that setup.rb gets the `--silent` flag.
  def test_execute_system_silent_passed_to_setuprb
    @cmd.options[:args] = []
    @cmd.options[:system] = true
    @cmd.options[:silent] = true

    assert_equal true, @cmd.update_rubygems_arguments.include?("--silent")
  end

  def test_execute_system_silent
    spec_fetcher do |fetcher|
      fetcher.download "rubygems-update", 9 do |s|
        s.files = %w[setup.rb]
      end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = true
    @cmd.options[:silent]        = true

    use_ui @ui do
      @cmd.execute
    end

    assert_empty @ui.output
  end

  # before:
  #   a1 -> c1.2
  # after:
  #   a2 -> b2 # new dependency
  #   a2 -> c2

  def test_execute_dependencies
    spec_fetcher do |fetcher|
      fetcher.download "a", 2, "b" => 2, "c" => 2
      fetcher.download "b", 2
      fetcher.download "c", 2

      fetcher.spec "a", 1, "c" => "1.2"
      fetcher.spec "c", "1.2"
    end

    Gem::Specification.reset

    @cmd.options[:args] = []

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating a", out.shift
    assert_equal "Gems updated: a b c",
                 out.shift

    assert_empty out
  end

  def test_execute_rdoc
    spec_fetcher do |fetcher|
      fetcher.download "a", 2
      fetcher.spec "a", 1
    end

    Gem.done_installing(&Gem::RDoc.method(:generation_hook))

    @cmd.options[:document] = %w[rdoc ri]

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    wait_for_child_process_to_exit

    a2 = @specs["a-2"]

    assert_path_exist File.join(a2.doc_dir, "rdoc")
  end if defined?(Gem::RDoc)

  def test_execute_named
    spec_fetcher do |fetcher|
      fetcher.download "a", 2

      fetcher.spec "a", 1
    end

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating a", out.shift
    assert_equal "Gems updated: a", out.shift

    assert_empty out
  end

  def test_execute_named_some_up_to_date
    spec_fetcher do |fetcher|
      fetcher.download "a", 2
      fetcher.spec "a", 1

      fetcher.spec "b", 2
    end

    @cmd.options[:args] = %w[a b]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems",    out.shift
    assert_equal "Updating a",                 out.shift
    assert_equal "Gems updated: a",            out.shift
    assert_equal "Gems already up-to-date: b", out.shift

    assert_empty out
  end

  def test_execute_named_up_to_date
    spec_fetcher do |fetcher|
      fetcher.spec "a", 2
    end

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Nothing to update", out.shift
    assert_equal "Gems already up-to-date: a", out.shift

    assert_empty out
  end

  def test_execute_named_up_to_date_prerelease
    spec_fetcher do |fetcher|
      fetcher.download "a", "3.a"

      fetcher.gem "a", 2
    end

    @cmd.options[:args] = %w[a]
    @cmd.options[:prerelease] = true

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating a", out.shift
    assert_equal "Gems updated: a", out.shift

    assert_empty out
  end

  def test_execute_up_to_date
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2
    end

    @cmd.options[:args] = []

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Nothing to update", out.shift

    assert_empty out
  end

  def test_execute_user_install
    a = util_spec "a", 1
    b = util_spec "b", 1
    install_gem_user(a)
    install_gem(b)

    @cmd.handle_options %w[--user-install]

    use_ui @ui do
      @cmd.execute
    end

    installer = @cmd.installer
    user_install = installer.instance_variable_get :@user_install

    assert user_install, "user_install must be set on the installer"

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating a", out.shift
    assert_equal "Gems updated: a", out.shift
    assert_empty out
  end

  def test_fetch_remote_gems
    specs = spec_fetcher do |fetcher|
      fetcher.gem "a", 1
      fetcher.gem "a", 2
    end

    expected = [
      [Gem::NameTuple.new("a", v(2), Gem::Platform::RUBY),
       Gem::Source.new(@gem_repo)],
    ]

    assert_equal expected, @cmd.fetch_remote_gems(specs["a-1"])
  end

  def test_fetch_remote_gems_error
    Gem.sources.replace %w[http://nonexistent.example]

    assert_raise Gem::RemoteFetcher::FetchError do
      @cmd.fetch_remote_gems @specs["a-1"]
    end
  end

  def test_fetch_remote_gems_mismatch
    platform = Gem::Platform.new "x86-freebsd9"

    specs = spec_fetcher do |fetcher|
      fetcher.spec "a", 1
      fetcher.spec "a", 2

      fetcher.spec "a", 2 do |s|
        s.platform = platform
      end
    end

    expected = [
      [Gem::NameTuple.new("a", v(2), Gem::Platform::RUBY),
       Gem::Source.new(@gem_repo)],
    ]

    assert_equal expected, @cmd.fetch_remote_gems(specs["a-1"])
  end

  def test_fetch_remote_gems_prerelease
    specs = spec_fetcher do |fetcher|
      fetcher.gem "a", 1
      fetcher.gem "a", 2
      fetcher.gem "a", "3.a"
    end

    @cmd.options[:prerelease] = true

    expected = [
      [Gem::NameTuple.new("a", v(2), Gem::Platform::RUBY),
       Gem::Source.new(@gem_repo)],
      [Gem::NameTuple.new("a", v("3.a"), Gem::Platform::RUBY),
       Gem::Source.new(@gem_repo)],
    ]

    assert_equal expected, @cmd.fetch_remote_gems(specs["a-1"])
  end

  def test_handle_options_system
    @cmd.handle_options %w[--system]

    expected = {
      args: [],
      document: %w[ri],
      force: false,
      system: true,
    }

    assert_equal expected, @cmd.options
  end

  def test_handle_options_system_non_version
    assert_raise ArgumentError do
      @cmd.handle_options %w[--system non-version]
    end
  end

  def test_handle_options_system_specific
    @cmd.handle_options %w[--system 1.3.7]

    expected = {
      args: [],
      document: %w[ri],
      force: false,
      system: "1.3.7",
    }

    assert_equal expected, @cmd.options
  end

  def test_update_gem_prerelease
    spec_fetcher do |fetcher|
      fetcher.spec "a", "1.a"
      fetcher.gem  "a", "1.b"
    end

    @cmd.update_gem "a", Gem::Requirement.new("= 1.b")

    refute_empty @cmd.updated

    assert @cmd.installer.instance_variable_get :@prerelease
  end

  def test_update_gem_unresolved_dependency
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
      fetcher.gem  "a", 2 do |s|
        s.add_dependency "b", ">= 2"
      end

      fetcher.spec "b", 1
    end

    @cmd.update_gem "a"

    assert_empty @cmd.updated
  end

  def test_update_rubygems_arguments
    @cmd.options[:system] = true

    arguments = @cmd.update_rubygems_arguments

    assert_equal "--prefix",           arguments.shift
    assert_equal Gem.prefix,           arguments.shift
    assert_equal "--no-document",      arguments.shift
    assert_equal "--previous-version", arguments.shift
    assert_equal Gem::VERSION,         arguments.shift
    assert_empty arguments
  end

  def test_explain
    spec_fetcher do |fetcher|
      fetcher.download "a", 2
      fetcher.spec "a", 1
    end

    @cmd.options[:explain] = true
    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    assert_equal "Gems to update:", out.shift
    assert_equal "  a-2", out.shift
    assert_empty out
  end

  def test_explain_platform_local
    local = Gem::Platform.local
    spec_fetcher do |fetcher|
      fetcher.download "a", 2

      fetcher.download "a", 2 do |s|
        s.platform = local
      end

      fetcher.spec "a", 1
    end

    @cmd.options[:explain] = true
    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    assert_equal "Gems to update:", out.shift
    assert_equal "  a-2-#{local}", out.shift
    assert_empty out
  end

  def test_explain_platform_ruby
    local = Gem::Platform.local
    spec_fetcher do |fetcher|
      fetcher.download "a", 2

      fetcher.download "a", 2 do |s|
        s.platform = local
      end

      fetcher.spec "a", 1
    end

    # equivalent to --platform=ruby
    Gem.platforms = [Gem::Platform::RUBY]

    @cmd.options[:explain] = true
    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    assert_equal "Gems to update:", out.shift
    assert_equal "  a-2", out.shift
    assert_empty out
  end

  def test_execute_named_not_installed_and_no_update
    spec_fetcher do |fetcher|
      fetcher.spec "a", 2
    end

    @cmd.options[:args] = %w[a b]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Nothing to update", out.shift
    assert_equal "Gems already up-to-date: a", out.shift
    assert_equal "Gems not currently installed: b", out.shift

    assert_empty out
  end
end
