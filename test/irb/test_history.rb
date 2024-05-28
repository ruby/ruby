# frozen_string_literal: false
require 'irb'
require 'readline'
require "tempfile"

require_relative "helper"

return if RUBY_PLATFORM.match?(/solaris|mswin|mingw/i)

module TestIRB
  class HistoryTest < TestCase
    def setup
      @original_verbose, $VERBOSE = $VERBOSE, nil
      @tmpdir = Dir.mktmpdir("test_irb_history_")
      @backup_home = ENV["HOME"]
      @backup_xdg_config_home = ENV.delete("XDG_CONFIG_HOME")
      @backup_irbrc = ENV.delete("IRBRC")
      @backup_default_external = Encoding.default_external
      ENV["HOME"] = @tmpdir
      IRB.instance_variable_set(:@existing_rc_name_generators, nil)
    end

    def teardown
      IRB.instance_variable_set(:@existing_rc_name_generators, nil)
      ENV["HOME"] = @backup_home
      ENV["XDG_CONFIG_HOME"] = @backup_xdg_config_home
      ENV["IRBRC"] = @backup_irbrc
      Encoding.default_external = @backup_default_external
      $VERBOSE = @original_verbose
      FileUtils.rm_rf(@tmpdir)
    end

    class TestInputMethodWithRelineHistory < TestInputMethod
      # When IRB.conf[:USE_MULTILINE] is true, IRB::RelineInputMethod uses Reline::History
      HISTORY = Reline::History.new(Reline.core.config)

      include IRB::HistorySavingAbility
    end

    class TestInputMethodWithReadlineHistory < TestInputMethod
      # When IRB.conf[:USE_MULTILINE] is false, IRB::ReadlineInputMethod uses Readline::HISTORY
      HISTORY = Readline::HISTORY

      include IRB::HistorySavingAbility
    end

    def test_history_save_1
      omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
      IRB.conf[:SAVE_HISTORY] = 1
      assert_history(<<~EXPECTED_HISTORY, <<~INITIAL_HISTORY, <<~INPUT)
        exit
      EXPECTED_HISTORY
        1
        2
        3
        4
      INITIAL_HISTORY
        5
        exit
      INPUT
    end

    def test_history_save_100
      omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
      IRB.conf[:SAVE_HISTORY] = 100
      assert_history(<<~EXPECTED_HISTORY, <<~INITIAL_HISTORY, <<~INPUT)
        1
        2
        3
        4
        5
        exit
      EXPECTED_HISTORY
        1
        2
        3
        4
      INITIAL_HISTORY
        5
        exit
      INPUT
    end

    def test_history_save_bignum
      omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
      IRB.conf[:SAVE_HISTORY] = 10 ** 19
      assert_history(<<~EXPECTED_HISTORY, <<~INITIAL_HISTORY, <<~INPUT)
        1
        2
        3
        4
        5
        exit
      EXPECTED_HISTORY
        1
        2
        3
        4
      INITIAL_HISTORY
        5
        exit
      INPUT
    end

    def test_history_save_minus_as_infinity
      omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
      IRB.conf[:SAVE_HISTORY] = -1 # infinity
      assert_history(<<~EXPECTED_HISTORY, <<~INITIAL_HISTORY, <<~INPUT)
        1
        2
        3
        4
        5
        exit
      EXPECTED_HISTORY
        1
        2
        3
        4
      INITIAL_HISTORY
        5
        exit
      INPUT
    end

    def test_history_concurrent_use_reline
      omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
      IRB.conf[:SAVE_HISTORY] = 1
      history_concurrent_use_for_input_method(TestInputMethodWithRelineHistory)
    end

    def test_history_concurrent_use_readline
      omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
      IRB.conf[:SAVE_HISTORY] = 1
      history_concurrent_use_for_input_method(TestInputMethodWithReadlineHistory)
    end

    def test_history_concurrent_use_not_present
      IRB.conf[:LC_MESSAGES] = IRB::Locale.new
      IRB.conf[:SAVE_HISTORY] = 1
      io = TestInputMethodWithRelineHistory.new
      io.class::HISTORY.clear
      io.load_history
      io.class::HISTORY << 'line1'
      io.class::HISTORY << 'line2'

      history_file = IRB.rc_file("_history")
      assert_not_send [File, :file?, history_file]
      File.write(history_file, "line0\n")
      io.save_history
      assert_equal(%w"line0 line1 line2", File.read(history_file).split)
    end

    def test_history_different_encodings
      IRB.conf[:SAVE_HISTORY] = 2
      Encoding.default_external = Encoding::US_ASCII
      locale = IRB::Locale.new("C")
      assert_history(<<~EXPECTED_HISTORY.encode(Encoding::US_ASCII), <<~INITIAL_HISTORY.encode(Encoding::UTF_8), <<~INPUT, locale: locale)
        ????
        exit
      EXPECTED_HISTORY
        😀
      INITIAL_HISTORY
        exit
      INPUT
    end

    def test_history_does_not_raise_when_history_file_directory_does_not_exist
      backup_history_file = IRB.conf[:HISTORY_FILE]
      IRB.conf[:SAVE_HISTORY] = 1
      IRB.conf[:HISTORY_FILE] = "fake/fake/fake/history_file"
      io = TestInputMethodWithRelineHistory.new

      assert_warn(/history file does not exist/) do
        io.save_history
      end

      # assert_warn reverts $VERBOSE to EnvUtil.original_verbose, which is true in some cases
      # We want to keep $VERBOSE as nil until teardown is called
      # TODO: check if this is an assert_warn issue
      $VERBOSE = nil
    ensure
      IRB.conf[:HISTORY_FILE] = backup_history_file
    end

    def test_no_home_no_history_file_does_not_raise_history_save
      ENV['HOME'] = nil
      io = TestInputMethodWithRelineHistory.new
      assert_nil(IRB.rc_file('_history'))
      assert_nothing_raised do
        io.load_history
        io.save_history
      end
    end

    private

    def history_concurrent_use_for_input_method(input_method)
      assert_history(<<~EXPECTED_HISTORY, <<~INITIAL_HISTORY, <<~INPUT, input_method) do |history_file|
        exit
        5
        exit
      EXPECTED_HISTORY
        1
        2
        3
        4
      INITIAL_HISTORY
        5
        exit
      INPUT
        assert_history(<<~EXPECTED_HISTORY2, <<~INITIAL_HISTORY2, <<~INPUT2, input_method)
        exit
      EXPECTED_HISTORY2
        1
        2
        3
        4
      INITIAL_HISTORY2
        5
        exit
      INPUT2
        File.utime(File.atime(history_file), File.mtime(history_file) + 2, history_file)
      end
    end

    def assert_history(expected_history, initial_irb_history, input, input_method = TestInputMethodWithRelineHistory, locale: IRB::Locale.new)
      IRB.conf[:LC_MESSAGES] = locale
      actual_history = nil
      history_file = IRB.rc_file("_history")
      ENV["HOME"] = @tmpdir
      File.open(history_file, "w") do |f|
        f.write(initial_irb_history)
      end

      io = input_method.new
      io.class::HISTORY.clear
      io.load_history
      if block_given?
        previous_history = []
        io.class::HISTORY.each { |line| previous_history << line }
        yield history_file
        io.class::HISTORY.clear
        previous_history.each { |line| io.class::HISTORY << line }
      end
      input.split.each { |line| io.class::HISTORY << line }
      io.save_history

      io.load_history
      File.open(history_file, "r") do |f|
        actual_history = f.read
      end
      assert_equal(expected_history, actual_history, <<~MESSAGE)
        expected:
        #{expected_history}
        but actual:
        #{actual_history}
      MESSAGE
    end

    def with_temp_stdio
      Tempfile.create("test_readline_stdin") do |stdin|
        Tempfile.create("test_readline_stdout") do |stdout|
          yield stdin, stdout
        end
      end
    end
  end

  class IRBHistoryIntegrationTest < IntegrationTestCase
    def test_history_saving_with_debug
      write_history ""

      write_ruby <<~'RUBY'
        def foo
        end

        binding.irb

        foo
      RUBY

      output = run_ruby_file do
        type "'irb session'"
        type "next"
        type "'irb:debug session'"
        type "step"
        type "irb_info"
        type "puts Reline::HISTORY.to_a.to_s"
        type "q!"
      end

      assert_include(output, "InputMethod: RelineInputMethod")
      # check that in-memory history is preserved across sessions
      assert_include output, %q(
        ["'irb session'", "next", "'irb:debug session'", "step", "irb_info", "puts Reline::HISTORY.to_a.to_s"]
      ).strip

      assert_equal <<~HISTORY, @history_file.open.read
        'irb session'
        next
        'irb:debug session'
        step
        irb_info
        puts Reline::HISTORY.to_a.to_s
        q!
      HISTORY
    end

    def test_history_saving_with_debug_without_prior_history
      tmpdir = Dir.mktmpdir("test_irb_history_")
      # Intentionally not creating the file so we test the reset counter logic
      history_file = File.join(tmpdir, "irb_history")

      write_rc <<~RUBY
        IRB.conf[:HISTORY_FILE] = "#{history_file}"
      RUBY

      write_ruby <<~'RUBY'
        def foo
        end

        binding.irb

        foo
      RUBY

      output = run_ruby_file do
        type "'irb session'"
        type "next"
        type "'irb:debug session'"
        type "step"
        type "irb_info"
        type "puts Reline::HISTORY.to_a.to_s"
        type "q!"
      end

      assert_include(output, "InputMethod: RelineInputMethod")
      # check that in-memory history is preserved across sessions
      assert_include output, %q(
        ["'irb session'", "next", "'irb:debug session'", "step", "irb_info", "puts Reline::HISTORY.to_a.to_s"]
      ).strip

      assert_equal <<~HISTORY, File.read(history_file)
        'irb session'
        next
        'irb:debug session'
        step
        irb_info
        puts Reline::HISTORY.to_a.to_s
        q!
      HISTORY
    ensure
      FileUtils.rm_rf(tmpdir)
    end

    def test_history_saving_with_nested_sessions
      write_history ""

      write_ruby <<~'RUBY'
        def foo
          binding.irb
        end

        binding.irb
      RUBY

      run_ruby_file do
        type "'outer session'"
        type "foo"
        type "'inner session'"
        type "exit"
        type "'outer session again'"
        type "exit"
      end

      assert_equal <<~HISTORY, @history_file.open.read
        'outer session'
        foo
        'inner session'
        exit
        'outer session again'
        exit
      HISTORY
    end

    def test_nested_history_saving_from_inner_session_with_exit!
      write_history ""

      write_ruby <<~'RUBY'
        def foo
          binding.irb
        end

        binding.irb
      RUBY

      run_ruby_file do
        type "'outer session'"
        type "foo"
        type "'inner session'"
        type "exit!"
      end

      assert_equal <<~HISTORY, @history_file.open.read
        'outer session'
        foo
        'inner session'
        exit!
      HISTORY
    end

    def test_nested_history_saving_from_outer_session_with_exit!
      write_history ""

      write_ruby <<~'RUBY'
        def foo
          binding.irb
        end

        binding.irb
      RUBY

      run_ruby_file do
        type "'outer session'"
        type "foo"
        type "'inner session'"
        type "exit"
        type "'outer session again'"
        type "exit!"
      end

      assert_equal <<~HISTORY, @history_file.open.read
        'outer session'
        foo
        'inner session'
        exit
        'outer session again'
        exit!
      HISTORY
    end

    def test_history_saving_with_nested_sessions_and_prior_history
      write_history <<~HISTORY
        old_history_1
        old_history_2
        old_history_3
      HISTORY

      write_ruby <<~'RUBY'
        def foo
          binding.irb
        end

        binding.irb
      RUBY

      run_ruby_file do
        type "'outer session'"
        type "foo"
        type "'inner session'"
        type "exit"
        type "'outer session again'"
        type "exit"
      end

      assert_equal <<~HISTORY, @history_file.open.read
        old_history_1
        old_history_2
        old_history_3
        'outer session'
        foo
        'inner session'
        exit
        'outer session again'
        exit
      HISTORY
    end

    private

    def write_history(history)
      @history_file = Tempfile.new('irb_history')
      @history_file.write(history)
      @history_file.close
      write_rc <<~RUBY
        IRB.conf[:HISTORY_FILE] = "#{@history_file.path}"
      RUBY
    end
  end
end
