# frozen_string_literal: false
require 'tempfile'
require 'irb'
require 'rubygems'

require_relative "helper"

module TestIRB
  class ContextWithTracerIntegrationTest < IntegrationTestCase
    def setup
      super

      @envs.merge!("NO_COLOR" => "true", "RUBY_DEBUG_HISTORY_FILE" => '')
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

    def test_use_tracer_is_disabled_by_default
      write_rc <<~RUBY
        IRB.conf[:USE_TRACER] = false
      RUBY

      write_ruby example_ruby_file

      output = run_ruby_file do
        type "bar(Foo)"
        type "exit!"
      end

      assert_nil IRB.conf[:USER_TRACER]
      assert_not_include(output, "#depth:")
      assert_not_include(output, "Foo.foo")
    end

    def test_use_tracer_enabled_when_gem_is_unavailable
      begin
        gem 'tracer'
        omit "Skipping because 'tracer' gem is available."
      rescue Gem::LoadError
        write_rc <<~RUBY
          IRB.conf[:USE_TRACER] = true
        RUBY

        write_ruby example_ruby_file

        output = run_ruby_file do
          type "bar(Foo)"
          type "exit!"
        end

        assert_include(output, "Tracer extension of IRB is enabled but tracer gem wasn't found.")
      end
    end

    def test_use_tracer_enabled_when_gem_is_available
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.1.0')
        omit "Ruby version before 3.1.0 does not support Tracer integration. Skipping this test."
      end

      begin
        gem 'tracer'
      rescue Gem::LoadError
        omit "Skipping because 'tracer' gem is not available. Enable with WITH_TRACER=true."
      end

      write_rc <<~RUBY
        IRB.conf[:USE_TRACER] = true
      RUBY

      write_ruby example_ruby_file

      output = run_ruby_file do
        type "bar(Foo)"
        type "exit!"
      end

      assert_include(output, "Object#bar at")
      assert_include(output, "Foo.foo at")
      assert_include(output, "Foo.foo #=> 100")
      assert_include(output, "Object#bar #=> 100")
    end
  end
end
