# frozen_string_literal: false
require 'tempfile'
require 'irb'

require_relative "helper"

module TestIRB
  class ContextWithTracerIntegrationTest < IntegrationTestCase
    def setup
      super

      omit "Tracer gem is not available when running on TruffleRuby" if RUBY_ENGINE == "truffleruby"

      @envs.merge!("NO_COLOR" => "true")
    end

    def example_ruby_file
      <<~'RUBY'
        class Foo
          def self.foo
            100
          end
        end

        def bar(obj)
          obj.foo
        end

        binding.irb
      RUBY
    end

    def test_use_tracer_enabled_when_gem_is_unavailable
      write_rc <<~RUBY
        # Simulate the absence of the tracer gem
        ::Kernel.send(:alias_method, :irb_original_require, :require)

        ::Kernel.define_method(:require) do |name|
          raise LoadError, "cannot load such file -- tracer (test)" if name.match?("tracer")
          ::Kernel.send(:irb_original_require, name)
        end

        IRB.conf[:USE_TRACER] = true
      RUBY

      write_ruby example_ruby_file

      output = run_ruby_file do
        type "bar(Foo)"
        type "exit"
      end

      assert_include(output, "Tracer extension of IRB is enabled but tracer gem wasn't found.")
    end

    def test_use_tracer_enabled_when_gem_is_available
      write_rc <<~RUBY
        IRB.conf[:USE_TRACER] = true
      RUBY

      write_ruby example_ruby_file

      output = run_ruby_file do
        type "bar(Foo)"
        type "exit"
      end

      assert_include(output, "Object#bar at")
      assert_include(output, "Foo.foo at")
      assert_include(output, "Foo.foo #=> 100")
      assert_include(output, "Object#bar #=> 100")

      # Test that the tracer output does not include IRB's own files
      assert_not_include(output, "irb/workspace.rb")
    end

    def test_use_tracer_is_disabled_by_default
      write_ruby example_ruby_file

      output = run_ruby_file do
        type "bar(Foo)"
        type "exit"
      end

      assert_not_include(output, "#depth:")
      assert_not_include(output, "Foo.foo")
    end

  end
end
