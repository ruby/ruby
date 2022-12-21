# frozen_string_literal: false
require 'irb'
require 'irb/ext/save-history'
require 'readline'

require_relative "helper"

module TestIRB
  class TestHistory < TestCase
    def setup
      IRB.conf[:RC_NAME_GENERATOR] = nil
    end

    def teardown
      IRB.conf[:RC_NAME_GENERATOR] = nil
    end

    class TestInputMethodWithHistory < TestInputMethod
      HISTORY = Array.new

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

    def test_history_concurrent_use
      omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
      IRB.conf[:SAVE_HISTORY] = 1
      assert_history(<<~EXPECTED_HISTORY, <<~INITIAL_HISTORY, <<~INPUT) do |history_file|
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
        assert_history(<<~EXPECTED_HISTORY2, <<~INITIAL_HISTORY2, <<~INPUT2)
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

    def test_history_concurrent_use_not_present
      backup_home = ENV["HOME"]
      backup_xdg_config_home = ENV.delete("XDG_CONFIG_HOME")
      backup_irbrc = ENV.delete("IRBRC")
      IRB.conf[:LC_MESSAGES] = IRB::Locale.new
      IRB.conf[:SAVE_HISTORY] = 1
      Dir.mktmpdir("test_irb_history_") do |tmpdir|
        ENV["HOME"] = tmpdir
        io = TestInputMethodWithHistory.new
        io.class::HISTORY.clear
        io.load_history
        io.class::HISTORY.concat(%w"line1 line2")

        history_file = IRB.rc_file("_history")
        assert_not_send [File, :file?, history_file]
        File.write(history_file, "line0\n")
        io.save_history
        assert_equal(%w"line0 line1 line2", File.read(history_file).split)
      end
    ensure
      ENV["HOME"] = backup_home
      ENV["XDG_CONFIG_HOME"] = backup_xdg_config_home
      ENV["IRBRC"] = backup_irbrc
    end

    private

    def assert_history(expected_history, initial_irb_history, input)
      backup_verbose, $VERBOSE = $VERBOSE, nil
      backup_home = ENV["HOME"]
      backup_xdg_config_home = ENV.delete("XDG_CONFIG_HOME")
      IRB.conf[:LC_MESSAGES] = IRB::Locale.new
      actual_history = nil
      Dir.mktmpdir("test_irb_history_") do |tmpdir|
        ENV["HOME"] = tmpdir
        File.open(IRB.rc_file("_history"), "w") do |f|
          f.write(initial_irb_history)
        end

        io = TestInputMethodWithHistory.new
        io.class::HISTORY.clear
        io.load_history
        if block_given?
          history = io.class::HISTORY.dup
          yield IRB.rc_file("_history")
          io.class::HISTORY.replace(history)
        end
        io.class::HISTORY.concat(input.split)
        io.save_history

        io.load_history
        File.open(IRB.rc_file("_history"), "r") do |f|
          actual_history = f.read
        end
      end
      assert_equal(expected_history, actual_history, <<~MESSAGE)
        expected:
        #{expected_history}
        but actual:
        #{actual_history}
      MESSAGE
    ensure
      $VERBOSE = backup_verbose
      ENV["HOME"] = backup_home
      ENV["XDG_CONFIG_HOME"] = backup_xdg_config_home
    end

    def with_temp_stdio
      Tempfile.create("test_readline_stdin") do |stdin|
        Tempfile.create("test_readline_stdout") do |stdout|
          yield stdin, stdout
        end
      end
    end
  end
end if not RUBY_PLATFORM.match?(/solaris|mswin|mingw/i)
