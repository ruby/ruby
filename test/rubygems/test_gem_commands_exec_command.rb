# frozen_string_literal: true
require_relative "helper"
require "rubygems/commands/exec_command"

class TestGemCommandsExecCommand < Gem::TestCase
  def setup
    super
    common_installer_setup

    @cmd = Gem::Commands::ExecCommand.new

    @orig_args = Gem::Command.build_args

    common_installer_setup
  end

  def teardown
    super

    common_installer_teardown

    Gem::Command.build_args = @orig_args
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
        :explicit_prerelease => false,
        gem_name: "cocoapods",
        prerelease: false,
        :version => Gem::Requirement.new(["> 1", "< 1.3"]),
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
        :version => Gem::Requirement.new([">= 0"]),
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
        :version => Gem::Requirement.new(["= 7.1"]),
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

        write_file File.join(*%W[gems #{s.original_name}      bin a]) do |f|
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

  def test_gem_with_other_executable_name
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
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

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
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

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end

        write_file File.join(*%W[gems #{s.original_name}      bin a]) do |f|
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

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end

        write_file File.join(*%W[gems #{s.original_name}      bin bar]) do |f|
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

        write_file File.join(*%W[gems #{s.original_name}      bin a]) do |f|
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

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
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

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
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
        ERROR:  Possible alternatives: a
      ERR
    end
  end

  def test_pre_argument
    spec_fetcher do |fetcher|
      fetcher.gem "a", 1 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
      fetcher.gem "a", "1.1.a" do |s|
        s.executables = %w[foo ]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
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
      fetcher.gem "a", 1 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
      fetcher.gem "a", "1.1.a" do |s|
        s.executables = %w[foo ]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    util_clear_gems

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

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
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
        ERROR:  Possible alternatives: a
      ERROR
    end
  end

  def test_conservative
    spec_fetcher do |fetcher|
      fetcher.gem "a", 1 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    util_clear_gems

    use_ui @ui do
      @cmd.invoke "--verbose", "--conservative", "a"
      assert_include @ui.output, "a (>= 0) not available locally"
      assert_include @ui.output, "a-1 foo"
    end

    @ui.outs.truncate(0)

    spec_fetcher do |fetcher|
      fetcher.gem "a", 1 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end

      fetcher.gem "a", 2 do |s|
        s.executables = %w[foo]
        s.files = %w[bin/foo lib/a.rb]

        write_file File.join(*%W[gems #{s.original_name}      bin foo]) do |f|
          f << "Gem.ui.say #{s.original_name.dump} + ' ' + File.basename(__FILE__)"
        end
      end
    end

    use_ui @ui do
      @cmd.invoke "--verbose", "--conservative", "a"
      assert_not_include @ui.output, "a (>= 0) not available locally"
      assert_include @ui.output, "a-1 foo"
    end
  end
end
