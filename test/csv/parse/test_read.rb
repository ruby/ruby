# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVParseRead < Test::Unit::TestCase
  extend DifferentOFS

  def test_shift
    data = <<-CSV
1
2
3
    CSV
    csv = CSV.new(data)
    assert_equal([
                   ["1"],
                   [["2"], ["3"]],
                   nil,
                 ],
                 [
                   csv.shift,
                   csv.read,
                   csv.shift,
                 ])
  end
end
