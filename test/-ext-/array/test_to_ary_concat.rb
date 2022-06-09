# frozen_string_literal: false
require 'test/unit'
require '-test-/array/to_ary_concat'

class TestConcatStress < Test::Unit::TestCase
  def setup
    @stress_level = GC.stress
    GC.stress = true
  end

  def teardown
    GC.stress = @stress_level
  end

  def test_concat
    arr = [nil]
    bar = Bug::Bar.new
    arr.concat(bar)
  end
end
