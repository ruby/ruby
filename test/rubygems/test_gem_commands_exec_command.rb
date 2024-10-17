# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/exec_command"

class TestGemCommandsExecCommand < Gem::TestCase
  def setup
    @orig_args = Gem::Command.build_args
    @orig_specific_extra_args = Gem::Command.specific_extra_args_hash.dup
    @orig_extra_args = Gem::Command.extra_args.dup

    super
    common_installer_setup

    @cmd = Gem::Commands::ExecCommand.new

    @gem_home = Gem.dir
    @gem_path = Gem.path
    @test_arch = RbConfig::CONFIG["arch"]

    @installed_specs = []
    Gem.post_install {|installer| @installed_specs << installer.spec }
  end

  def teardown
    super

    common_installer_teardown

    Gem::Command.build_args = @orig_args
    Gem::Command.specific_extra_args_hash = @orig_specific_extra_args
    Gem::Command.extra_args = @orig_extra_args
    Gem.configuration = nil
  end

  def invoke(*args)
    @ui.outs.truncate(0)
    @ui.outs.rewind
    @ui.errs.truncate(0)
    @ui.errs.rewind
    @installed_specs.clear

    @cmd.invoke(*args)
  ensure
    Gem::Specification.unresolved_deps.clear
    Gem.loaded_specs.clear
    Gem.instance_variable_set(:@activated_gem_paths, 0)
    Gem.clear_default_specs
    Gem.use_paths(@gem_home, @gem_path)
    Gem.refresh
  end

  def test_error_with_no_arguments
    e = assert_raise Gem::CommandLineError do
      @cmd.invoke
    end
    assert_equal "Please specify an executable to run (e.g. gem exec COMMAND)",
      e.message
  end

  def test_error_with_no_executable
    e = assert_raise Gem::CommandLineError do
      @cmd.invoke "--verbose", "--gem", "GEM", "--version", "< 10", "--conservative"
    end
    assert_equal "Please specify an executable to run (e.g. gem exec COMMAND)",
      e.message
  end

  def test_full_option_parsing
    @cmd.when_invoked do |options|
      assert_equal options, {
        args: ["install", "--no-color", "--help", "--verbose"],
        executable: "pod",
        explicit_prerelease: false,
        gem_name: "cocoapods",
        prerelease: false,
        version: Gem::Requirement.new(["> 1", "< 1.3"]),
        build_args: nil,
      }
    end
    @cmd.invoke "--gem", "cocoapods", "-v", "> 1", "--version", "< 1.3", "--verbose", "--", "pod", "install", "--no-color", "--help", "--verbose"
  end

  def test_single_arg_parsing
    @cmd.when_invoked do |options|
      assert_equal options, {
        args: [],
        executable: "rails",
        gem_name: "rails",
        version: Gem::Requirement.new([">= 0"]),
        build_args: nil,
      }
    end
    @cmd.invoke "rails"
  end

  def test_single_arg_parsing_with_version
    @cmd.when_invoked do |options|
      assert_equal options, {
        args: [],
        executable: "rails",
        gem_name: "rails",
        version: Gem::Requirement.new(["= 7.1"]),
        build_args: nil,
      }
    end
    @cmd.invoke "rails:7.1"
  end

  def test_gem_without_executable
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2
    end

    util_clear_gems

    use_ui @ui do
      e = assert_raise Gem::MockGemUi::TermError, @ui.error do
        @cmd.invoke "a:2"
      end
      assert_equal 1, e.exit_code
      assert_equal "ERROR:  Failed to load executable `a`, are you sure the gem `a` contains it?\n", @ui.error
    end
  end

  def test_gem_with_executable
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2 do |s|
        s.executables = %w[a]
        s.files = %w[bin/a lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << "Gem.ui.say #{s.original_name.dump}"
        end
      end
    end

    util_clear_gems

    use_ui @ui do
      @cmd.invoke "a:2"
      assert_equal "a-2\n", @ui.output
    end
  end

  def test_gem_with_platforms
    spec_fetcher do |fetcher|
      fetcher.download "a", 2 do |s|
        s.executables = %w[a]
        s.files = %w[bin/a lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << "Gem.ui.say #{s.original_name.dump}"
        end
      end

      fetcher.download "a", 2 do |s|
        s.executables = %w[a]
        s.files = %w[bin/a lib/a.rb]
        s.platform = "x86_64-darwin"

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << "Gem.ui.say #{s.original_name.dump}"
        end
      end
    end

    use_ui @ui do
      invoke "a:2"
      assert_equal "a-2\n", @ui.output
    end

    use_ui @ui do
      util_set_arch "x86_64-darwin-18"
      invoke "a:2"
      assert_equal "a-2-x86_64-darwin\n", @ui.output
    end
  end

  def test_gem_with_platform_dependencies
    spec_fetcher do |fetcher|
      fetcher.download "a", 2 do |s|
        s.executables = %w[a]
        s.files = %w[bin/a lib/a.rb]
        s.add_dependency "with_platform"

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << 'require "with_platform"' << "\n"
          f << 'Gem.ui.say Gem.loaded_specs.each_value.map(&:original_name).sort.join("\n")'
        end
      end

      fetcher.download "with_platform", 2 do |s|
        s.files = %w[lib/with_platform.rb]
        s.platform = Gem::Platform.local
      end

      fetcher.download "with_platform", 2 do |s|
        s.files = %w[lib/with_platform.rb]
      end
    end

    use_ui @ui do
      util_set_arch "unknown-unknown"
      invoke "a"
      assert_equal "a-2\nwith_platform-2\n", @ui.output
    end

    use_ui @ui do
      util_set_arch @test_arch
      invoke "a"
      assert_empty @ui.error
      assert_equal "a-2\nwith_platform-2-#{Gem::Platform.local}\n", @ui.output
    end
  end

  def test_gem_with_platform_and_platform_dependencies
    pend "needs investigation" if Gem.java_platform?
    pend "terminates on mswin" if vc_windows? && ruby_repo?

    spec_fetcher do |fetcher|
      fetcher.download "a", 2 do |s|
        s.executables = %w[a]
        s.files = %w[bin/a lib/a.rb]
        s.add_dependency "with_platform"
        s.platform = Gem::Platform.local.to_s

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << 'require "with_platform"' << "\n"
          f << 'Gem.ui.say Gem.loaded_specs.each_value.map(&:original_name).sort.join("\n")'
        end
      end

      fetcher.download "a", 2 do |s|
        s.executables = %w[a]
        s.files = %w[bin/a lib/a.rb extconf.rb]
        s.add_dependency "with_platform"

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << 'require "with_platform"' << "\n"
          f << 'Gem.ui.say Gem.loaded_specs.each_value.map(&:original_name).sort.join("\n")'
        end

        s.extensions = %w[extconf.rb]
        write_file File.join(*%W[gems #{s.original_name} extconf.rb]) do |f|
          f.write <<-RUBY
            gem('with_platform', '~> 2.0')
            require 'with_platform'
            gem 'sometimes_used'
            require 'sometimes_used'
            require "mkmf"
            create_makefile("#{s.name}")
          RUBY
        end
      end

      fetcher.download "with_platform", 2 do |s|
        s.files = %w[lib/with_platform.rb]
        s.platform = Gem::Platform.local.to_s
      end

      fetcher.download "with_platform", 2 do |s|
        s.files = %w[lib/with_platform.rb]
        s.add_dependency "sometimes_used"
      end

      fetcher.download "sometimes_used", 2 do |s|
        s.files = %w[lib/sometimes_used.rb]
      end
    end

    use_ui @ui do
      util_set_arch "unknown-unknown"
      invoke "a"
      assert_empty @ui.error
      assert_equal "Building native extensions. This could take a while...\na-2\nsometimes_used-2\nwith_platform-2\n", @ui.output
    end

    use_ui @ui do
      util_set_arch @test_arch
      invoke "a"
      assert_empty @ui.error
      assert_equal "a-2-#{Gem::Platform.local}\nwith_platform-2-#{Gem::Platform.local}\n", @ui.output
    end
  end

  def test_gem_with_other_executable_name
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump}"
        end
      end
    end

    util_clear_gems

    use_ui @ui do
      @cmd.invoke "a:2"
      assert_equal "a-2\n", @ui.output
    end
  end

  def test_gem_with_executable_error
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "raise #{s.original_name.dump}"
        end
      end
    end

    util_clear_gems

    use_ui @ui do
      e = assert_raise RuntimeError do
        @cmd.invoke "a:2"
      end
      assert_equal "a-2", e.message
      assert_empty @ui.error
    end
  end

  def test_gem_with_multiple_executables_one_match
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2 do |s|
        s.executables = %w[foo a]
        s.files = %w[bin/foo bin/a lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    util_clear_gems

    use_ui @ui do
      @cmd.invoke "a:2"
      assert_equal "a-2 a\n", @ui.output
    end
  end

  def test_gem_with_multiple_executables_no_match
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2 do |s|
        s.executables = %w[foo bar]
        s.files = %w[bin/foo bin/bar lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end

        write_file File.join(*%W[gems #{s.original_name} bin bar]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    util_clear_gems

    use_ui @ui do
      @cmd.invoke "a:2"
      assert_equal "a-2 foo\n", @ui.output
    end
  end

  def test_gem_dependency_contains_executable
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2 do |s|
        s.executables = %w[]
        s.files = %w[lib/a.rb]

        s.add_dependency "b"
      end

      fetcher.gem "b", 2 do |s|
        s.executables = %w[a]
        s.files = %w[bin/a lib/b.rb]

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    util_clear_gems

    use_ui @ui do
      @cmd.invoke "a:2"
      assert_equal "b-2 a\n", @ui.output
    end
  end

  def test_gem_dependency_contains_other_executable
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2 do |s|
        s.executables = %w[]
        s.files = %w[lib/a.rb]

        s.add_dependency "b"
      end

      fetcher.gem "b", 2 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/b.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    util_clear_gems

    use_ui @ui do
      e = assert_raise Gem::MockGemUi::TermError do
        @cmd.invoke "a:2"
      end
      assert_equal 1, e.exit_code
      assert_equal <<~ERR, @ui.error
        ERROR:  Failed to load executable `a`, are you sure the gem `a` contains it?
      ERR
    end
  end

  def test_other_gem_contains_executable
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2 do |s|
        s.executables = %w[]
        s.files = %w[lib/a.rb]
      end

      fetcher.gem "b", 2 do |s|
        s.executables = %w[a]
        s.files = %w[bin/a lib/b.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    util_clear_gems

    use_ui @ui do
      e = assert_raise Gem::MockGemUi::TermError do
        @cmd.invoke "a:2"
      end
      assert_equal 1, e.exit_code
      assert_equal <<~ERR, @ui.error
        ERROR:  Failed to load executable `a`, are you sure the gem `a` contains it?
      ERR
    end
  end

  def test_missing_gem
    spec_fetcher do |fetcher|
    end

    use_ui @ui do
      e = assert_raise Gem::MockGemUi::TermError do
        @cmd.invoke "a"
      end
      assert_equal 2, e.exit_code
      assert_equal <<~ERR, @ui.error
        ERROR:  Could not find a valid gem 'a' (>= 0) in any repository
      ERR
    end
  end

  def test_version_mismatch
    spec_fetcher do |fetcher|
      fetcher.gem "a", 1
    end

    util_clear_gems

    use_ui @ui do
      e = assert_raise Gem::MockGemUi::TermError do
        @cmd.invoke "a:2"
      end
      assert_equal 2, e.exit_code
      assert_equal <<~ERR, @ui.error
        ERROR:  Could not find a valid gem 'a' (= 2) in any repository
      ERR
    end
  end

  def test_pre_argument
    spec_fetcher do |fetcher|
      fetcher.gem "a", 1 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
      fetcher.gem "a", "1.1.a" do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    util_clear_gems

    use_ui @ui do
      @cmd.invoke "--pre", "a"
      assert_equal "a-1.1.a foo\n", @ui.output
    end
  end

  def test_pre_version_option
    spec_fetcher do |fetcher|
      fetcher.download "a", 1 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
      fetcher.download "a", "1.1.a" do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    use_ui @ui do
      @cmd.invoke "-v", ">= 0.a", "a"
      assert_equal "a-1.1.a foo\n", @ui.output
    end
  end

  def test_conservative_missing_gem
    spec_fetcher do |fetcher|
      fetcher.gem "a", 1 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    util_clear_gems

    use_ui @ui do
      e = assert_raise Gem::MockGemUi::TermError do
        @cmd.invoke "--verbose", "--conservative", "a:2"
      end
      assert_equal 2, e.exit_code
      assert_include @ui.output, "a (= 2) not available locally"
      assert_equal <<~ERROR, @ui.error
        ERROR:  Could not find a valid gem 'a' (= 2) in any repository
      ERROR
    end
  end

  def test_conservative
    spec_fetcher do |fetcher|
      fetcher.download "a", 1 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    use_ui @ui do
      invoke "--verbose", "--conservative", "a"
      assert_include @ui.output, "a (>= 0) not available locally"
      assert_include @ui.output, "a-1 foo"
      assert_equal %w[a-1], @installed_specs.map(&:original_name)
    end

    spec_fetcher do |fetcher|
      fetcher.gem "a", 1 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end

      fetcher.download "a", 2 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    use_ui @ui do
      invoke "--verbose", "--conservative", "a"
      assert_not_include @ui.output, "a (>= 0) not available locally"
      assert_include @ui.output, "a-1 foo"
      assert_empty @installed_specs.map(&:original_name)
    end
  end

  def test_uses_newest_version
    spec_fetcher do |fetcher|
      fetcher.download "a", 1 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    use_ui @ui do
      invoke "a"
      assert_include @ui.output, "a-1 foo"
    end

    spec_fetcher do |fetcher|
      fetcher.download "a", 1 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end

      fetcher.download "a", 2 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    use_ui @ui do
      invoke "--verbose", "a:2"
      refute_predicate @ui, :terminated?
      assert_empty @ui.error
      assert_include @ui.output, "a-2 foo"
      assert_equal %w[a-2], @installed_specs.map(&:original_name)
    end
  end

  def test_uses_newest_version_of_dependency
    spec_fetcher do |fetcher|
      fetcher.gem "a", 1 do |s|
        s.executables = %w[]
        s.files = %w[lib/a.rb]
        s.add_dependency "b"
      end

      fetcher.gem "b", 1 do |s|
        s.executables = %w[a]
        s.files = %w[bin/a lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end

      fetcher.download "b", 2 do |s|
        s.executables = %w[a]
        s.files = %w[bin/a lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    use_ui @ui do
      invoke "a"
      assert_include @ui.output, "b-2 a"
      assert_equal %w[b-2], @installed_specs.map(&:original_name)
    end
  end

  def test_gem_exec_gem_uninstall
    spec_fetcher do |fetcher|
      fetcher.download "a", 2 do |s|
        s.executables = %w[a]
        s.files = %w[bin/a lib/a.rb]
        s.add_dependency "b"

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << "Gem.ui.say #{s.original_name.dump}"
        end
      end

      fetcher.download "b", 2 do |s|
        s.files = %w[lib/b.rb]
      end
    end

    use_ui @ui do
      invoke "a:2"
      assert_equal "a-2\n", @ui.output

      invoke "gem", "list", "--local"
      assert_includes @ui.output, "a (2)\n"
      assert_includes @ui.output, "b (2)\n"

      begin
        invoke "gem", "uninstall", "--verbose", "-x", "a"
      rescue StandardError
        nil
      end

      assert_empty @ui.error
      refute_includes @ui.output, "running gem exec with"
      assert_includes @ui.output, "Successfully uninstalled a-2\n"

      invoke "--verbose", "gem", "uninstall", "b"
      assert_includes @ui.output, "Successfully uninstalled b-2\n"

      invoke "gem", "list", "--local"
      assert_empty @ui.error
      assert_match(/\A\s*\** LOCAL GEMS \**\s*\z/m, @ui.output)

      invoke "gem", "env", "GEM_HOME"
      assert_equal "#{@gem_home}\n", @ui.output
    end
  end

  def test_only_prerelease_available
    spec_fetcher do |fetcher|
      fetcher.download "a", "1.a" do |s|
        s.executables = %w[a]
        s.files = %w[lib/a.rb bin/a]

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    use_ui @ui do
      assert_raise Gem::MockGemUi::TermError do
        invoke "a"
      end
      assert_equal "ERROR:  Could not find a valid gem 'a' (>= 0) in any repository\n", @ui.error
      assert_empty @ui.output
      assert_empty @installed_specs
    end

    use_ui @ui do
      invoke "a:1.a"
      assert_empty @ui.error
      assert_equal "a-1.a a\n", @ui.output
      assert_equal %w[a-1.a], @installed_specs.map(&:full_name)
    end

    FileUtils.rm_rf Gem.dir

    use_ui @ui do
      invoke "--version", ">= 1.a", "a"
      assert_empty @ui.error
      assert_equal "a-1.a a\n", @ui.output
      assert_equal %w[a-1.a], @installed_specs.map(&:full_name)
    end

    FileUtils.rm_rf Gem.dir

    use_ui @ui do
      invoke "--pre", "a"
      assert_empty @ui.error
      assert_equal "a-1.a a\n", @ui.output
      assert_equal %w[a-1.a], @installed_specs.map(&:full_name)
    end
  end

  def test_newer_prerelease_available
    spec_fetcher do |fetcher|
      fetcher.download "a", "1" do |s|
        s.executables = %w[a]
        s.files = %w[lib/a.rb bin/a]

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end

      fetcher.download "a", "1.1.a" do |s|
        s.executables = %w[a]
        s.files = %w[lib/a.rb bin/a]

        write_file File.join(*%W[gems #{s.original_name} bin a]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    use_ui @ui do
      invoke "a"
      assert_empty @ui.error
      assert_equal "a-1 a\n", @ui.output
      assert_equal %w[a-1], @installed_specs.map(&:full_name)
    end

    FileUtils.rm_rf Gem.dir

    use_ui @ui do
      invoke "a:1.1.a"
      assert_empty @ui.error
      assert_equal "a-1.1.a a\n", @ui.output
      assert_equal %w[a-1.1.a], @installed_specs.map(&:full_name)
    end

    FileUtils.rm_rf Gem.dir

    use_ui @ui do
      invoke "--version", ">= 1.a", "a"
      assert_empty @ui.error
      assert_equal "a-1.1.a a\n", @ui.output
      assert_equal %w[a-1.1.a], @installed_specs.map(&:full_name)
    end

    FileUtils.rm_rf Gem.dir

    use_ui @ui do
      invoke "--pre", "a"
      assert_empty @ui.error
      assert_equal "a-1.1.a a\n", @ui.output
      assert_equal %w[a-1.1.a], @installed_specs.map(&:full_name)
    end
  end
end
