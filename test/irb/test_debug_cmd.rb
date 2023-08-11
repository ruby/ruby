# frozen_string_literal: true

require "tempfile"
require "tmpdir"

require_relative "helper"

module TestIRB
  class DebugCommandTest < IntegrationTestCase
    def setup
      super

      if RUBY_ENGINE == 'truffleruby'
        omit "This test runs with ruby/debug, which doesn't work with truffleruby"
      end

      @envs.merge!("NO_COLOR" => "true", "RUBY_DEBUG_HISTORY_FILE" => '')
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
  end
end
