# frozen_string_literal: true
begin
  require_relative 'helper'
rescue LoadError
  return
end

module Fiddle
  class TestPinned < Fiddle::TestCase
    def test_pin_object
      x = Object.new
      pinner = Pinned.new x
      assert_same x, pinner.ref
    end

    def test_clear
      pinner = Pinned.new Object.new
      refute pinner.cleared?
      pinner.clear
      assert pinner.cleared?
      ex = assert_raise(Fiddle::ClearedReferenceError) do
        pinner.ref
      end
      assert_match "called on", ex.message
    end
  end
end

