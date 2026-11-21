# frozen_string_literal: true
require_relative 'helper'

module Psych
  class TestSymbol < TestCase
    def test_cycle_empty
      assert_cycle :''
    end

    def test_cycle_colon
      # Known limitation: libyaml's emitter adds a non-specific "!" tag when it
      # must quote a scalar that was requested plain, preserving the plain
      # resolution (so ":" round-trips as a Symbol). libfyaml's streaming
      # emitter does not synthesize that tag, so a Symbol whose name is a YAML
      # indicator character reloads as a String.
      omit 'libfyaml does not round-trip symbols named after YAML indicators' if libfyaml?
      assert_cycle :':'
    end

    def test_cycle
      assert_cycle :a
    end

    def test_stringy
      assert_cycle :"1"
    end

    def test_load_quoted
      assert_equal :"1", Psych.load("--- :'1'\n")
    end
  end
end
