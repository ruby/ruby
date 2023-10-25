# frozen_string_literal: true

require_relative "helper"

class TestCSVPatternMatching < Test::Unit::TestCase

  def test_hash
    case CSV::Row.new(%i{A B C}, [1, 2, 3])
    in B: b, C: c
      assert_equal([2, 3], [b, c])
    end
  end

  def test_hash_rest
    case CSV::Row.new(%i{A B C}, [1, 2, 3])
    in B: b, **rest
      assert_equal([2, { A: 1, C: 3 }], [b, rest])
    end
  end

  def test_array
    case CSV::Row.new(%i{A B C}, [1, 2, 3])
    in *, matched
      assert_equal(3, matched)
    end
  end
end
