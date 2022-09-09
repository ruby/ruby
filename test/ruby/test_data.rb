# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'

class TestData < Test::Unit::TestCase
  def test_empty
    assert_raise_with_message(ArgumentError, /expected 1\+/) {
      Data.define()
    }
  end

  def test_def
    data = Data.define(:a, :b)
    assert_equal(data.new(1, 2), data.new(1, 2))

    assert_raise_with_message(ArgumentError, /\bmissing argument a\b/) {
      data.new
    }
    assert_raise_with_message(ArgumentError, /\bgiven 3, expected 2\b/) {
      data.new(1, 2, 3)
    }
    assert_raise_with_message(ArgumentError, /\bmissing argument b\b/) {
      data.new(a: 1)
    }
  end
end
