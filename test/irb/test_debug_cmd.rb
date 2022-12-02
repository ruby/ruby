# frozen_string_literal: true

require "pty" unless RUBY_ENGINE == 'truffleruby'
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
      if ENV["GITHUB_ACTION_REPOSITORY"] != "ruby/irb"
        omit "This test works only on ruby/irb CI"
      end
    end

    def test_backtrace
      omit if RUBY_ENGINE == 'truffleruby'
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
      omit if RUBY_ENGINE == 'truffleruby'
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
      omit if RUBY_ENGINE == 'truffleruby'
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
      omit if RUBY_ENGINE == 'truffleruby'
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
      omit if RUBY_ENGINE == 'truffleruby'
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
      omit if RUBY_ENGINE == 'truffleruby'
      write_ruby <<~'RUBY'
        def foo
          puts "Hello"
        end
        binding.irb
        foo
      RUBY

      output = run_ruby_file do
        type "step"
        type "continue"
      end

      assert_match(/\(rdbg:irb\) step/, output)
      assert_match(/=>   2|   puts "Hello"/, output)
    end

    def test_continue
      omit if RUBY_ENGINE == 'truffleruby'
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
      omit if RUBY_ENGINE == 'truffleruby'
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
      omit if RUBY_ENGINE == 'truffleruby'
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
      omit if RUBY_ENGINE == 'truffleruby'
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
        Timeout.timeout(3) do
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
