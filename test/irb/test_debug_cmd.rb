# frozen_string_literal: true

begin
  require "pty"
rescue LoadError
  return
end

require "tempfile"
require "tmpdir"
require "envutil"

require_relative "helper"

module TestIRB
  LIB = File.expand_path("../../lib", __dir__)

  class DebugCommandTestCase < TestCase
    IRB_AND_DEBUGGER_OPTIONS = {
      "RUBY_DEBUG_NO_RELINE" => "true", "NO_COLOR" => "true", "RUBY_DEBUG_HISTORY_FILE" => ''
    }

    def setup
      if ruby_core?
        omit "This test works only under ruby/irb"
      end

      if RUBY_ENGINE == 'truffleruby'
        omit "This test runs with ruby/debug, which doesn't work with truffleruby"
      end
    end

    def test_backtrace
      write_ruby <<~'RUBY'
        def foo
          binding.irb
        end
        foo
      RUBY

      output = run_ruby_file do
        type "backtrace"
        type "q!"
      end

      assert_match(/\(rdbg:irb\) backtrace/, output)
      assert_match(/Object#foo at #{@ruby_file.to_path}/, output)
    end

    def test_debug
      write_ruby <<~'ruby'
        binding.irb
        puts "hello"
      ruby

      output = run_ruby_file do
        type "debug"
        type "next"
        type "continue"
      end

      assert_match(/\(rdbg\) next/, output)
      assert_match(/=>   2\| puts "hello"/, output)
    end

    def test_next
      write_ruby <<~'ruby'
        binding.irb
        puts "hello"
      ruby

      output = run_ruby_file do
        type "next"
        type "continue"
      end

      assert_match(/\(rdbg:irb\) next/, output)
      assert_match(/=>   2\| puts "hello"/, output)
    end

    def test_break
      write_ruby <<~'RUBY'
        binding.irb
        puts "Hello"
      RUBY

      output = run_ruby_file do
        type "break 2"
        type "continue"
        type "continue"
      end

      assert_match(/\(rdbg:irb\) break/, output)
      assert_match(/=>   2\| puts "Hello"/, output)
    end

    def test_delete
      write_ruby <<~'RUBY'
        binding.irb
        puts "Hello"
        binding.irb
        puts "World"
      RUBY

      output = run_ruby_file do
        type "break 4"
        type "continue"
        type "delete 0"
        type "continue"
      end

      assert_match(/\(rdbg:irb\) delete/, output)
      assert_match(/deleted: #0  BP - Line/, output)
    end

    def test_step
      write_ruby <<~'RUBY'
        def foo
          puts "Hello"
        end
        binding.irb
        foo
      RUBY

      output = run_ruby_file do
        type "step"
        type "step"
        type "continue"
      end

      assert_match(/\(rdbg:irb\) step/, output)
      assert_match(/=>   5\| foo/, output)
      assert_match(/=>   2\|   puts "Hello"/, output)
    end

    def test_continue
      write_ruby <<~'RUBY'
        binding.irb
        puts "Hello"
        binding.irb
        puts "World"
      RUBY

      output = run_ruby_file do
        type "continue"
        type "continue"
      end

      assert_match(/\(rdbg:irb\) continue/, output)
      assert_match(/=> 3: binding.irb/, output)
    end

    def test_finish
      write_ruby <<~'RUBY'
        def foo
          binding.irb
          puts "Hello"
        end
        foo
      RUBY

      output = run_ruby_file do
        type "finish"
        type "continue"
      end

      assert_match(/\(rdbg:irb\) finish/, output)
      assert_match(/=>   4\| end/, output)
    end

    def test_info
      write_ruby <<~'RUBY'
        def foo
          a = "He" + "llo"
          binding.irb
        end
        foo
      RUBY

      output = run_ruby_file do
        type "info"
        type "continue"
      end

      assert_match(/\(rdbg:irb\) info/, output)
      assert_match(/%self = main/, output)
      assert_match(/a = "Hello"/, output)
    end

    def test_catch
      write_ruby <<~'RUBY'
        binding.irb
        1 / 0
      RUBY

      output = run_ruby_file do
        type "catch ZeroDivisionError"
        type "continue"
        type "continue"
      end

      assert_match(/\(rdbg:irb\) catch/, output)
      assert_match(/Stop by #0  BP - Catch  "ZeroDivisionError"/, output)
    end

    private

    TIMEOUT_SEC = 3

    def run_ruby_file(&block)
      cmd = [EnvUtil.rubybin, "-I", LIB, @ruby_file.to_path]
      tmp_dir = Dir.mktmpdir
      rc_file = File.open(File.join(tmp_dir, ".irbrc"), "w+")
      rc_file.write("IRB.conf[:USE_SINGLELINE] = true")
      rc_file.close

      @commands = []
      lines = []

      yield

      PTY.spawn(IRB_AND_DEBUGGER_OPTIONS.merge("IRBRC" => rc_file.to_path), *cmd) do |read, write, pid|
        Timeout.timeout(TIMEOUT_SEC) do
          while line = safe_gets(read)
            lines << line

            # means the breakpoint is triggered
            if line.match?(/binding\.irb/)
              while command = @commands.shift
                write.puts(command)
              end
            end
          end
        end
      ensure
        read.close
        write.close
        kill_safely(pid)
      end

      lines.join
    rescue Timeout::Error
      message = <<~MSG
      Test timedout.

      #{'=' * 30} OUTPUT #{'=' * 30}
        #{lines.map { |l| "  #{l}" }.join}
      #{'=' * 27} END OF OUTPUT #{'=' * 27}
      MSG
      assert_block(message) { false }
    ensure
      File.unlink(@ruby_file) if @ruby_file
      FileUtils.remove_entry tmp_dir
    end

    # read.gets could raise exceptions on some platforms
    # https://github.com/ruby/ruby/blob/master/ext/pty/pty.c#L729-L736
    def safe_gets(read)
      read.gets
    rescue Errno::EIO
      nil
    end

    def kill_safely pid
      return if wait_pid pid, TIMEOUT_SEC

      Process.kill :TERM, pid
      return if wait_pid pid, 0.2

      Process.kill :KILL, pid
      Process.waitpid(pid)
    rescue Errno::EPERM, Errno::ESRCH
    end

    def wait_pid pid, sec
      total_sec = 0.0
      wait_sec = 0.001 # 1ms

      while total_sec < sec
        if Process.waitpid(pid, Process::WNOHANG) == pid
          return true
        end
        sleep wait_sec
        total_sec += wait_sec
        wait_sec *= 2
      end

      false
    rescue Errno::ECHILD
      true
    end

    def type(command)
      @commands << command
    end

    def write_ruby(program)
      @ruby_file = Tempfile.create(%w{irb- .rb})
      @ruby_file.write(program)
      @ruby_file.close
    end
  end
end
