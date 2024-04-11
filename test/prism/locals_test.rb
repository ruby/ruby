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
    invalid = []
    todos = []

    # Invalid break
    invalid << "break.txt"
    invalid << "if.txt"
    invalid << "rescue.txt"
    invalid << "seattlerb/block_break.txt"
    invalid << "unless.txt"
    invalid << "whitequark/break.txt"
    invalid << "whitequark/break_block.txt"

    # Invalid next
    invalid << "next.txt"
    invalid << "seattlerb/block_next.txt"
    invalid << "unparser/corpus/literal/control.txt"
    invalid << "whitequark/next.txt"
    invalid << "whitequark/next_block.txt"

    # Invalid redo
    invalid << "keywords.txt"
    invalid << "whitequark/redo.txt"

    # Invalid retry
    invalid << "whitequark/retry.txt"

    # Invalid yield
    invalid << "seattlerb/dasgn_icky2.txt"
    invalid << "seattlerb/yield_arg.txt"
    invalid << "seattlerb/yield_call_assocs.txt"
    invalid << "seattlerb/yield_empty_parens.txt"
    invalid << "unparser/corpus/literal/yield.txt"
    invalid << "whitequark/args_assocs.txt"
    invalid << "whitequark/args_assocs_legacy.txt"
    invalid << "whitequark/yield.txt"
    invalid << "yield.txt"

    # Dead code eliminated
    invalid << "whitequark/ruby_bug_10653.txt"

    base = File.join(__dir__, "fixtures")
    skips = invalid | todos

    Dir["**/*.txt", base: base].each do |relative|
      next if skips.include?(relative)

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
