# frozen_string_literal: true

require_relative "helper"
require "rubygems/command"

class Gem::Command
  public :parser
end

class TestGemCommand < Gem::TestCase
  def setup
    super

    @xopt = nil

    @common_options = Gem::Command.common_options.dup
    Gem::Command.common_options.clear
    Gem::Command.common_options << [
      ["-x", "--exe", "Execute"], lambda do |*_a|
        @xopt = true
      end
    ]

    @cmd_name = "doit"
    @cmd = Gem::Command.new @cmd_name, "summary"
  end

  def teardown
    super
    Gem::Command.common_options.replace @common_options
  end

  def test_self_add_specific_extra_args
    added_args = %w[--all]
    @cmd.add_option("--all") {|v,o| }

    Gem::Command.add_specific_extra_args @cmd_name, added_args

    assert_equal added_args, Gem::Command.specific_extra_args(@cmd_name)

    h = @cmd.add_extra_args []

    assert_equal added_args, h
  end

  def test_self_add_specific_extra_args_unknown
    added_args = %w[--definitely_not_there]

    Gem::Command.add_specific_extra_args @cmd_name, added_args

    assert_equal added_args, Gem::Command.specific_extra_args(@cmd_name)

    h = @cmd.add_extra_args []

    assert_equal [], h
  end

  def test_self_extra_args
    verbose = $VERBOSE
    $VERBOSE = nil
    separator = $;
    extra_args = Gem::Command.extra_args

    Gem::Command.extra_args = %w[--all]
    assert_equal %w[--all], Gem::Command.extra_args

    Gem::Command.extra_args = "--file --help"
    assert_equal %w[--file --help], Gem::Command.extra_args

    $; = "="

    Gem::Command.extra_args = "--awesome=true --verbose"
    assert_equal %w[--awesome=true --verbose], Gem::Command.extra_args
  ensure
    Gem::Command.extra_args = extra_args
    $; = separator
    $VERBOSE = verbose
  end

  def test_basic_accessors
    assert_equal "doit", @cmd.command
    assert_equal "gem doit", @cmd.program_name
    assert_equal "summary", @cmd.summary
  end

  def test_common_option_in_class
    assert Array === Gem::Command.common_options
  end

  def test_defaults
    @cmd.add_option("-h", "--help [COMMAND]", "Get help on COMMAND") do |value, options|
      options[:help] = value
    end

    @cmd.defaults = { help: true }

    @cmd.when_invoked do |options|
      assert options[:help], "Help options should default true"
    end

    use_ui @ui do
      @cmd.invoke
    end

    assert_match(/Usage: gem doit/, @ui.output)
  end

  def test_invoke
    done = false
    @cmd.when_invoked { done = true }

    use_ui @ui do
      @cmd.invoke
    end

    assert done
  end

  def test_invoke_with_bad_options
    use_ui @ui do
      @cmd.when_invoked { true }

      ex = assert_raise Gem::OptionParser::InvalidOption do
        @cmd.invoke("-zzz")
      end

      assert_match(/invalid option:/, ex.message)
    end
  end

  def test_invoke_with_common_options
    @cmd.when_invoked { true }

    use_ui @ui do
      @cmd.invoke "-x"
    end

    assert @xopt, "Should have done xopt"
  end

  def test_invoke_with_build_args
    @cmd.when_invoked { true }

    use_ui @ui do
      @cmd.invoke_with_build_args ["-x"], ["--awesome=true"]
    end

    assert_equal ["--awesome=true"], @cmd.options[:build_args]
  end

  # Returning false from the command handler invokes the usage output.
  def test_invoke_with_help
    done = false

    use_ui @ui do
      @cmd.add_option("-h", "--help [COMMAND]", "Get help on COMMAND") do |_value, options|
        options[:help] = true
        done = true
      end

      @cmd.invoke("--help")

      assert done
    end

    assert_match(/Usage/, @ui.output)
    assert_match(/gem doit/, @ui.output)
    assert_match(/\[options\]/, @ui.output)
    assert_match(/-h/, @ui.output)
    assert_match(/--help \[COMMAND\]/, @ui.output)
    assert_match(/Get help on COMMAND/, @ui.output)
    assert_match(/-x/, @ui.output)
    assert_match(/--exe/, @ui.output)
    assert_match(/Execute/, @ui.output)
    assert_match(/Common Options:/, @ui.output)
  end

  def test_invoke_with_options
    @cmd.add_option("-h", "--help [COMMAND]", "Get help on COMMAND") do |_value, options|
      options[:help] = true
    end

    @cmd.when_invoked do |opts|
      assert opts[:help]
    end

    use_ui @ui do
      @cmd.invoke "-h"
    end

    assert_match(/Usage: gem doit/, @ui.output)
  end

  def test_add_option
    assert_nothing_raised RuntimeError do
      @cmd.add_option("--force", "skip validation of the spec") {|v,o| }
    end
  end

  def test_add_option_with_empty
    assert_raise RuntimeError, "Do not pass an empty string in opts" do
      @cmd.add_option("", "skip validation of the spec") {|v,o| }
    end
  end

  def test_option_recognition
    @cmd.add_option("-h", "--help [COMMAND]", "Get help on COMMAND") do |_value, options|
      options[:help] = true
    end
    @cmd.add_option("-f", "--file FILE", "File option") do |_value, options|
      options[:help] = true
    end
    @cmd.add_option("--silent", "Silence RubyGems output") do |_value, options|
      options[:silent] = true
    end
    assert @cmd.handles?(["-x"])
    assert @cmd.handles?(["-h"])
    assert @cmd.handles?(["-h", "command"])
    assert @cmd.handles?(["--help", "command"])
    assert @cmd.handles?(["-f", "filename"])
    assert @cmd.handles?(["--file=filename"])
    assert @cmd.handles?(["--silent"])
    refute @cmd.handles?(["-z"])
    refute @cmd.handles?(["-f"])
    refute @cmd.handles?(["--toothpaste"])

    args = ["-h", "command"]
    @cmd.handles?(args)
    assert_equal ["-h", "command"], args
  end

  def test_deprecate_option
    deprecate_msg = <<-EXPECTED
WARNING:  The \"--test\" option has been deprecated and will be removed in Rubygems 3.1.
    EXPECTED

    test_command = Class.new(Gem::Command) do
      def initialize
        super("test", "Gem::Command instance for testing")

        add_option("-t", "--test", "Test command") do |_value, options|
          options[:test] = true
        end

        deprecate_option("--test", version: "3.1")
      end

      def execute
        true
      end
    end

    cmd = test_command.new

    use_ui @ui do
      cmd.invoke("--test")
      assert_equal deprecate_msg, @ui.error
    end
  end

  def test_deprecate_option_no_version
    deprecate_msg = <<-EXPECTED
WARNING:  The \"--test\" option has been deprecated and will be removed in future versions of Rubygems.
    EXPECTED

    test_command = Class.new(Gem::Command) do
      def initialize
        super("test", "Gem::Command instance for testing")

        add_option("-t", "--test", "Test command") do |_value, options|
          options[:test] = true
        end

        deprecate_option("--test")
      end

      def execute
        true
      end
    end

    cmd = test_command.new

    use_ui @ui do
      cmd.invoke("--test")
      assert_equal deprecate_msg, @ui.error
    end
  end

  def test_deprecate_option_extra_message
    deprecate_msg = <<-EXPECTED
WARNING:  The \"--test\" option has been deprecated and will be removed in Rubygems 3.1. Whether you set `--test` mode or not, this dummy app always runs in test mode.
    EXPECTED

    test_command = Class.new(Gem::Command) do
      def initialize
        super("test", "Gem::Command instance for testing")

        add_option("-t", "--test", "Test command") do |_value, options|
          options[:test] = true
        end

        deprecate_option("--test", version: "3.1", extra_msg: "Whether you set `--test` mode or not, this dummy app always runs in test mode.")
      end

      def execute
        true
      end
    end

    cmd = test_command.new

    use_ui @ui do
      cmd.invoke("--test")
      assert_equal deprecate_msg, @ui.error
    end
  end

  def test_deprecate_option_extra_message_and_no_version
    deprecate_msg = <<-EXPECTED
WARNING:  The \"--test\" option has been deprecated and will be removed in future versions of Rubygems. Whether you set `--test` mode or not, this dummy app always runs in test mode.
    EXPECTED

    test_command = Class.new(Gem::Command) do
      def initialize
        super("test", "Gem::Command instance for testing")

        add_option("-t", "--test", "Test command") do |_value, options|
          options[:test] = true
        end

        deprecate_option("--test", extra_msg: "Whether you set `--test` mode or not, this dummy app always runs in test mode.")
      end

      def execute
        true
      end
    end

    cmd = test_command.new

    use_ui @ui do
      cmd.invoke("--test")
      assert_equal deprecate_msg, @ui.error
    end
  end

  def test_show_lookup_failure_suggestions_local
    correct    = "non_existent_with_hint"
    misspelled = "nonexistent_with_hint"

    spec_fetcher do |fetcher|
      fetcher.spec correct, 2
    end

    use_ui @ui do
      @cmd.show_lookup_failure misspelled, Gem::Requirement.default, [], :local
    end

    expected = <<-EXPECTED
ERROR:  Could not find a valid gem 'nonexistent_with_hint' (>= 0) in any repository
    EXPECTED

    assert_equal expected, @ui.error
  end

  def test_show_lookup_failure_suggestions_none
    spec_fetcher do |fetcher|
      fetcher.spec "correct", 2
    end

    use_ui @ui do
      @cmd.show_lookup_failure "other", Gem::Requirement.default, [], :remote
    end

    expected = <<-EXPECTED
ERROR:  Could not find a valid gem 'other' (>= 0) in any repository
    EXPECTED

    assert_equal expected, @ui.error
  end

  def test_show_lookup_failure_suggestions_remote
    correct    = "non_existent_with_hint"
    misspelled = "nonexistent_with_hint"

    spec_fetcher do |fetcher|
      fetcher.spec correct, 2
    end

    use_ui @ui do
      @cmd.show_lookup_failure misspelled, Gem::Requirement.default, []
    end

    expected = <<-EXPECTED
ERROR:  Could not find a valid gem 'nonexistent_with_hint' (>= 0) in any repository
ERROR:  Possible alternatives: non_existent_with_hint
    EXPECTED

    assert_equal expected, @ui.error
  end
end
