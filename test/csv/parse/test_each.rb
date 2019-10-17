# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVParseEach < Test::Unit::TestCase
  extend DifferentOFS

  def test_twice
    data = <<-CSV
Ruby,2.6.0,script
    CSV
    csv = CSV.new(data)
    assert_equal([
                   [["Ruby", "2.6.0", "script"]],
                   [],
                 ],
                 [
                   csv.to_a,
                   csv.to_a,
                 ])
  end
end
