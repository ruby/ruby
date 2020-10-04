# frozen_string_literal: false
require 'test/unit'
require 'irb'
require 'readline'

module TestIRB
  class TestHistory < Test::Unit::TestCase
    def setup
      IRB.conf[:RC_NAME_GENERATOR] = nil
    end

    def teardown
      IRB.conf[:RC_NAME_GENERATOR] = nil
    end

    def test_history_save_1
      omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
      assert_history_with_irbrc_and_irb_history(<<~EXPECTED_HISTORY, <<~IRBRC, <<~IRB_HISTORY) do |stdin|
        exit
      EXPECTED_HISTORY
        IRB.conf[:USE_READLINE] = true
        IRB.conf[:SAVE_HISTORY] = 1
        IRB.conf[:USE_READLINE] = true
      IRBRC
        1
        2
        3
        4
      IRB_HISTORY
        stdin.write("5\nexit\n")
      end
    end

    def test_history_save_100
      omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
      assert_history_with_irbrc_and_irb_history(<<~EXPECTED_HISTORY, <<~IRBRC, <<~IRB_HISTORY) do |stdin|
        1
        2
        3
        4
        5
        exit
      EXPECTED_HISTORY
        IRB.conf[:USE_READLINE] = true
        IRB.conf[:SAVE_HISTORY] = 100
        IRB.conf[:USE_READLINE] = true
      IRBRC
        1
        2
        3
        4
      IRB_HISTORY
        stdin.write("5\nexit\n")
      end
    end

    def test_history_save_bignum
      omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
      assert_history_with_irbrc_and_irb_history(<<~EXPECTED_HISTORY, <<~IRBRC, <<~IRB_HISTORY) do |stdin|
        1
        2
        3
        4
        5
        exit
      EXPECTED_HISTORY
        IRB.conf[:USE_READLINE] = true
        IRB.conf[:SAVE_HISTORY] = 10 ** 19
        IRB.conf[:USE_READLINE] = true
      IRBRC
        1
        2
        3
        4
      IRB_HISTORY
        stdin.write("5\nexit\n")
      end
    end

    def test_history_save_minus_as_infinity
      omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
      assert_history_with_irbrc_and_irb_history(<<~EXPECTED_HISTORY, <<~IRBRC, <<~IRB_HISTORY) do |stdin|
        1
        2
        3
        4
        5
        exit
      EXPECTED_HISTORY
        IRB.conf[:USE_READLINE] = true
        IRB.conf[:SAVE_HISTORY] = -1 # infinity
        IRB.conf[:USE_READLINE] = true
      IRBRC
        1
        2
        3
        4
      IRB_HISTORY
        stdin.write("5\nexit\n")
      end
    end

    private

    def assert_history_with_irbrc_and_irb_history(expected_history, irbrc, irb_history)
      result = nil
      result_history = nil
      backup_irbrc = ENV.delete("IRBRC")
      backup_home = ENV["HOME"]
      Dir.mktmpdir("test_irb_history_#{$$}") do |tmpdir|
        ENV["HOME"] = tmpdir
        open(IRB.rc_file, "w") do |f|
          f.write(irbrc)
        end
        open(IRB.rc_file("_history"), "w") do |f|
          f.write(irb_history)
        end

        with_temp_stdio do |stdin, stdout|
          yield(stdin, stdout)
          stdin.close
          stdout.flush
          system('ruby', '-Ilib', '-Itest', '-W0', '-rirb', '-e', 'IRB.start(__FILE__)', in: stdin.path, out: stdout.path, err: stdout.path)
          result = stdout.read
          stdout.close
        end
        open(IRB.rc_file("_history"), "r") do |f|
          result_history = f.read
        end
      end
      assert_equal(expected_history, result_history, <<~MESSAGE)
        expected:
        #{expected_history}
        but actual:
        #{result_history}
        and stdout and stderr ware
        #{result}
      MESSAGE
    ensure
      ENV["HOME"] = backup_home
      ENV["IRBRC"] = backup_irbrc
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
