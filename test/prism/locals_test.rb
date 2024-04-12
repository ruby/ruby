# frozen_string_literal: true

# This test is going to use the RubyVM::InstructionSequence class to compile
# local tables and compare against them to ensure we have the same locals in the
# same order. This is important to guarantee that we compile indices correctly
# on CRuby (in terms of compatibility).
#
# There have also been changes made in other versions of Ruby, so we only want
# to test on the most recent versions.
return if !defined?(RubyVM::InstructionSequence) || RUBY_VERSION < "3.4.0"

# Omit tests if running on a 32-bit machine because there is a bug with how
# Ruby is handling large ISeqs on 32-bit machines
return if RUBY_PLATFORM =~ /i686/

require_relative "test_helper"

module Prism
  class LocalsTest < TestCase
    base = File.join(__dir__, "fixtures")
    Dir["**/*.txt", base: base].each do |relative|
      # Skip this fixture because it has a different number of locals because
      # CRuby is eliminating dead code.
      next if relative == "whitequark/ruby_bug_10653.txt"

      filepath = File.join(base, relative)
      define_method("test_#{relative}") { assert_locals(filepath) }
    end

    def setup
      @previous_default_external = Encoding.default_external
      ignore_warnings { Encoding.default_external = Encoding::UTF_8 }
    end

    def teardown
      ignore_warnings { Encoding.default_external = @previous_default_external }
    end

    private

    def assert_locals(filepath)
      source = File.read(filepath)

      expected = Debug.cruby_locals(source)
      actual = Debug.prism_locals(source)

      assert_equal(expected, actual)
    end

    def ignore_warnings
      previous_verbosity = $VERBOSE
      $VERBOSE = nil
      yield
    ensure
      $VERBOSE = previous_verbosity
    end
  end
end
