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
  end
end
