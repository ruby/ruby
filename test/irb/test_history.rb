# frozen_string_literal: false
require 'test/unit'
require 'irb'
require 'irb/ext/save-history'
require 'readline'

module TestIRB
  class TestHistory < Test::Unit::TestCase
    def setup
      IRB.conf[:RC_NAME_GENERATOR] = nil
    end

    def teardown
      IRB.conf[:RC_NAME_GENERATOR] = nil
    end

    class TestInputMethod < ::IRB::InputMethod
      HISTORY = Array.new

      include IRB::HistorySavingAbility

      attr_reader :list, :line_no

      def initialize(list = [])
        super("test")
        @line_no = 0
        @list = list
      end

      def gets
        @list[@line_no]&.tap {@line_no += 1}
      end

      def eof?
        @line_no >= @list.size
      end

      def encoding
        Encoding.default_external
      end

      def reset
        @line_no = 0
      end

      def winsize
        [10, 20]
      end
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

    private

    def assert_history(expected_history, initial_irb_history, input)
      backup_verbose, $VERBOSE = $VERBOSE, nil
      backup_home = ENV["HOME"]
      backup_xdg_config_home = ENV.delete("XDG_CONFIG_HOME")
      IRB.conf[:LC_MESSAGES] = IRB::Locale.new
      actual_history = nil
      Dir.mktmpdir("test_irb_history_#{$$}") do |tmpdir|
        ENV["HOME"] = tmpdir
        open(IRB.rc_file("_history"), "w") do |f|
          f.write(initial_irb_history)
        end

        io = TestInputMethod.new
        io.class::HISTORY.clear
        io.load_history
        io.class::HISTORY.concat(input.split)
        io.save_history

        io.load_history
        open(IRB.rc_file("_history"), "r") do |f|
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
