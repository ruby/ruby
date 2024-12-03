# frozen_string_literal: false
require 'irb'

require_relative "../helper"

module TestIRB
  class ShowSourceTest < IntegrationTestCase
    def setup
      super

      write_rc <<~'RUBY'
        IRB.conf[:USE_PAGER] = false
      RUBY
    end

    def test_show_source
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source IRB.conf"
        type "exit"
      end

      assert_match(%r[/irb\/init\.rb], out)
    end

    def test_show_source_alias
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      out = run_ruby_file do
        type "$ IRB.conf"
        type "exit"
      end

      assert_match(%r[/irb\/init\.rb], out)
    end

    def test_show_source_with_missing_signature
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source foo"
        type "exit"
      end

      assert_match(%r[Couldn't locate a definition for foo], out)
    end

    def test_show_source_with_missing_constant
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source Foo"
        type "exit"
      end

      assert_match(%r[Couldn't locate a definition for Foo], out)
    end

    def test_show_source_with_eval_error
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source raise(Exception).itself"
        type "exit"
      end

      assert_match(%r[Couldn't locate a definition for raise\(Exception\)\.itself], out)
    end

    def test_show_source_string
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source 'IRB.conf'"
        type "exit"
      end

      assert_match(%r[/irb\/init\.rb], out)
    end

    def test_show_source_method_s
      write_ruby <<~RUBY
        class Baz
          def foo
          end
        end

        class Bar < Baz
          def foo
            super
          end
        end

        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source Bar#foo -s"
        type "exit"
      end

      assert_match(%r[#{@ruby_file.to_path}:2\s+def foo\r\n  end\r\n], out)
    end

    def test_show_source_method_s_with_incorrect_signature
      write_ruby <<~RUBY
        class Baz
          def foo
          end
        end

        class Bar < Baz
          def foo
            super
          end
        end

        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source Bar#fooo -s"
        type "exit"
      end

      assert_match(%r[Error: Couldn't locate a super definition for Bar#fooo], out)
    end

    def test_show_source_private_method
      write_ruby <<~RUBY
        class Bar
          private def foo
          end
        end
        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source Bar#foo"
        type "exit"
      end

      assert_match(%r[#{@ruby_file.to_path}:2\s+private def foo\r\n  end\r\n], out)
    end

    def test_show_source_private_singleton_method
      write_ruby <<~RUBY
        class Bar
          private def foo
          end
        end
        binding.irb
      RUBY

      out = run_ruby_file do
        type "bar = Bar.new"
        type "show_source bar.foo"
        type "exit"
      end

      assert_match(%r[#{@ruby_file.to_path}:2\s+private def foo\r\n  end\r\n], out)
    end

    def test_show_source_method_multiple_s
      write_ruby <<~RUBY
        class Baz
          def foo
          end
        end

        class Bar < Baz
          def foo
            super
          end
        end

        class Bob < Bar
          def foo
            super
          end
        end

        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source Bob#foo -ss"
        type "exit"
      end

      assert_match(%r[#{@ruby_file.to_path}:2\s+def foo\r\n  end\r\n], out)
    end

    def test_show_source_method_no_instance_method
      write_ruby <<~RUBY
        class Baz
        end

        class Bar < Baz
          def foo
            super
          end
        end

        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source Bar#foo -s"
        type "exit"
      end

      assert_match(%r[Error: Couldn't locate a super definition for Bar#foo], out)
    end

    def test_show_source_method_exceeds_super_chain
      write_ruby <<~RUBY
        class Baz
          def foo
          end
        end

        class Bar < Baz
          def foo
            super
          end
        end

        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source Bar#foo -ss"
        type "exit"
      end

      assert_match(%r[Error: Couldn't locate a super definition for Bar#foo], out)
    end

    def test_show_source_method_accidental_characters
      write_ruby <<~'RUBY'
        class Baz
          def foo
          end
        end

        class Bar < Baz
          def foo
            super
          end
        end

        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source Bar#foo -sddddd"
        type "exit"
      end

      assert_match(%r[#{@ruby_file.to_path}:2\s+def foo\r\n  end], out)
    end

    def test_show_source_receiver_super
      write_ruby <<~RUBY
        class Baz
          def foo
          end
        end

        class Bar < Baz
          def foo
            super
          end
        end

        binding.irb
      RUBY

      out = run_ruby_file do
        type "bar = Bar.new"
        type "show_source bar.foo -s"
        type "exit"
      end

      assert_match(%r[#{@ruby_file.to_path}:2\s+def foo\r\n  end], out)
    end

    def test_show_source_with_double_colons
      write_ruby <<~RUBY
        class Foo
        end

        class Foo
          class Bar
          end
        end

        binding.irb
      RUBY

      out = run_ruby_file do
        type "show_source ::Foo"
        type "exit"
      end

      assert_match(%r[#{@ruby_file.to_path}:1\s+class Foo\r\nend], out)

      out = run_ruby_file do
        type "show_source ::Foo::Bar"
        type "exit"
      end

      assert_match(%r[#{@ruby_file.to_path}:5\s+class Bar\r\n  end], out)
    end

    def test_show_source_keep_script_lines
      pend unless defined?(RubyVM.keep_script_lines)

      write_ruby <<~RUBY
        binding.irb
      RUBY

      out = run_ruby_file do
        type "def foo; end"
        type "show_source foo"
        type "exit"
      end

      assert_match(%r[#{@ruby_file.to_path}\(irb\):1\s+def foo; end], out)
    end

    def test_show_source_unavailable_source
      write_ruby <<~RUBY
        binding.irb
      RUBY

      out = run_ruby_file do
        type "RubyVM.keep_script_lines = false if defined?(RubyVM.keep_script_lines)"
        type "def foo; end"
        type "show_source foo"
        type "exit"
      end
      assert_match(%r[#{@ruby_file.to_path}\(irb\):2\s+Source not available], out)
    end

    def test_show_source_shows_binary_source
      write_ruby <<~RUBY
        # io-console is an indirect dependency of irb
        require "io/console"

        binding.irb
      RUBY

      out = run_ruby_file do
        # IO::ConsoleMode is defined in io-console gem's C extension
        type "show_source IO::ConsoleMode"
        type "exit"
      end

      # A safeguard to make sure the test subject is actually defined
      refute_match(/NameError/, out)
      assert_match(%r[Defined in binary file:.+io/console], out)
    end

    def test_show_source_with_constant_lookup
      write_ruby <<~RUBY
        X = 1
        module M
          Y = 1
          Z = 2
        end
        class A
          Z = 1
          Array = 1
          class B
            include M
            Object.new.instance_eval { binding.irb }
          end
        end
      RUBY

      out = run_ruby_file do
        type "show_source X"
        type "show_source Y"
        type "show_source Z"
        type "show_source Array"
        type "exit"
      end

      assert_match(%r[#{@ruby_file.to_path}:1\s+X = 1], out)
      assert_match(%r[#{@ruby_file.to_path}:3\s+Y = 1], out)
      assert_match(%r[#{@ruby_file.to_path}:7\s+Z = 1], out)
      assert_match(%r[#{@ruby_file.to_path}:8\s+Array = 1], out)
    end
  end
end
