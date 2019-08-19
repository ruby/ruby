# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

module TestCSVWriteConverters
  def test_one
    assert_equal(%Q[=a,=b,=c\n],
                 generate_line(["a", "b", "c"],
                               write_converters: ->(value) {"=" + value}))
  end

  def test_multiple
    assert_equal(%Q[=a_,=b_,=c_\n],
                 generate_line(["a", "b", "c"],
                               write_converters: [
                                 ->(value) {"=" + value},
                                 ->(value) {value + "_"},
                               ]))
  end

  def test_nil_value
    assert_equal(%Q[a,NaN,c\n],
                 generate_line(["a", nil, "c"],
                               write_nil_value: "NaN"))
  end

  def test_empty_value
    assert_equal(%Q[a,,c\n],
                 generate_line(["a", "", "c"],
                               write_empty_value: nil))
  end
end

class TestCSVWriteConvertersGenerateLine < Test::Unit::TestCase
  include TestCSVWriteConverters
  extend DifferentOFS

  def generate_line(row, **kwargs)
    CSV.generate_line(row, **kwargs)
  end
end

class TestCSVWriteConvertersGenerate < Test::Unit::TestCase
  include TestCSVWriteConverters
  extend DifferentOFS

  def generate_line(row, **kwargs)
    CSV.generate(**kwargs) do |csv|
      csv << row
    end
  end
end
