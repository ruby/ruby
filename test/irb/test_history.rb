# frozen_string_literal: false
require 'test/unit'

module TestIRB
  class TestHistory < Test::Unit::TestCase
    def setup
      IRB.conf[:RC_NAME_GENERATOR] = nil
    end

    def teardown
      IRB.conf[:RC_NAME_GENERATOR] = nil
    end

    def test_history_save_1
      result_output, result_history_file = launch_irb_with_irbrc_and_irb_history(<<~IRBRC, <<~IRB_HISTORY) do |stdin|
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
      result_output, result_history_file = launch_irb_with_irbrc_and_irb_history(<<~IRBRC, <<~IRB_HISTORY) do |stdin|
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
          replace_stdio(stdin.path, stdout.path) do
            bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
            cmds = %W[ruby] + bundle_exec + %W[-W0 -rirb -e 'IRB.start(__FILE__)']
            yield(stdin, stdout)
            stdin.close
            system(cmds.join(' '))
            stdout.flush
            result = stdout.read
            stdout.close
          end
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

    def replace_stdio(stdin_path, stdout_path)
      open(stdin_path, "r") do |stdin|
        open(stdout_path, "w") do |stdout|
          orig_stdin = STDIN.dup
          orig_stdout = STDOUT.dup
          orig_stderr = STDERR.dup
          STDIN.reopen(stdin)
          STDOUT.reopen(stdout)
          STDERR.reopen(stdout)
          begin
            #Readline.input = STDIN
            #Readline.output = STDOUT
            yield
          ensure
            STDERR.reopen(orig_stderr)
            STDIN.reopen(orig_stdin)
            STDOUT.reopen(orig_stdout)
            orig_stdin.close
            orig_stdout.close
            orig_stderr.close
          end
        end
      end
    end
  end
end
