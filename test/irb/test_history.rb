# frozen_string_literal: false
require 'test/unit'
require 'irb'

module TestIRB
  class TestHistory < Test::Unit::TestCase
    def setup
      IRB.conf[:RC_NAME_GENERATOR] = nil
    end

    def teardown
      IRB.conf[:RC_NAME_GENERATOR] = nil
    end

    def test_history_save_1
      _result_output, result_history_file = launch_irb_with_irbrc_and_irb_history(<<~IRBRC, <<~IRB_HISTORY) do |stdin|
        IRB.conf[:USE_READLINE] = true
        IRB.conf[:SAVE_HISTORY] = 1
      IRBRC
        1
        2
        3
        4
      IRB_HISTORY
        stdin.write("5\nexit\n")
      end

      assert_equal(<<~HISTORY_FILE, result_history_file)
        exit
      HISTORY_FILE
    end

    def test_history_save_100
      _result_output, result_history_file = launch_irb_with_irbrc_and_irb_history(<<~IRBRC, <<~IRB_HISTORY) do |stdin|
        IRB.conf[:USE_READLINE] = true
        IRB.conf[:SAVE_HISTORY] = 100
      IRBRC
        1
        2
        3
        4
      IRB_HISTORY
        stdin.write("5\nexit\n")
      end

      assert_equal(<<~HISTORY_FILE, result_history_file)
        1
        2
        3
        4
        5
        exit
      HISTORY_FILE
    end

    def test_history_save_bignum
      _result_output, result_history_file = launch_irb_with_irbrc_and_irb_history(<<~IRBRC, <<~IRB_HISTORY) do |stdin|
        IRB.conf[:USE_READLINE] = true
        IRB.conf[:SAVE_HISTORY] = 10 ** 19
      IRBRC
        1
        2
        3
        4
      IRB_HISTORY
        stdin.write("5\nexit\n")
      end

      assert_equal(<<~HISTORY_FILE, result_history_file)
        1
        2
        3
        4
        5
        exit
      HISTORY_FILE
    end

    def test_history_save_minus_as_infinity
      _result_output, result_history_file = launch_irb_with_irbrc_and_irb_history(<<~IRBRC, <<~IRB_HISTORY) do |stdin|
        IRB.conf[:USE_READLINE] = true
        IRB.conf[:SAVE_HISTORY] = -1 # infinity
      IRBRC
        1
        2
        3
        4
      IRB_HISTORY
        stdin.write("5\nexit\n")
      end

      assert_equal(<<~HISTORY_FILE, result_history_file)
        1
        2
        3
        4
        5
        exit
      HISTORY_FILE
    end

    private

    def launch_irb_with_irbrc_and_irb_history(irbrc, irb_history)
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
          system('ruby', '-Ilib', '-Itest', '-W0', '-rirb', '-e', 'IRB.start(__FILE__)', in: stdin.path, out: stdout.path)
          result = stdout.read
          stdout.close
        end
        open(IRB.rc_file("_history"), "r") do |f|
          result_history = f.read
        end
      end
      [result, result_history]
    ensure
      ENV["HOME"] = backup_home
      ENV["IRBRC"] = backup_irbrc
    end

    def with_temp_stdio
      Tempfile.create("test_readline_stdin") do |stdin|
        Tempfile.create("test_readline_stdout") do |stdout|
          yield stdin, stdout
          if /mswin|mingw/ =~ RUBY_PLATFORM
            # needed since readline holds refs to tempfiles, can't delete on Windows
            #Readline.input = STDIN
            #Readline.output = STDOUT
          end
        end
      end
    end
  end
end if not RUBY_PLATFORM.match?(/solaris/i)
