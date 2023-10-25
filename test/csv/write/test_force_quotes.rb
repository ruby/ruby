# frozen_string_literal: false

require_relative "../helper"

module TestCSVWriteForceQuotes
  def test_default
    assert_equal(%Q[1,2,3#{$INPUT_RECORD_SEPARATOR}],
                 generate_line(["1", "2", "3"]))
  end

  def test_true
    assert_equal(%Q["1","2","3"#{$INPUT_RECORD_SEPARATOR}],
                 generate_line(["1", "2", "3"],
                               force_quotes: true))
  end

  def test_false
    assert_equal(%Q[1,2,3#{$INPUT_RECORD_SEPARATOR}],
                 generate_line(["1", "2", "3"],
                               force_quotes: false))
  end

  def test_field_name
    assert_equal(%Q["1",2,"3"#{$INPUT_RECORD_SEPARATOR}],
                 generate_line(["1", "2", "3"],
                               headers: ["a", "b", "c"],
                               force_quotes: ["a", :c]))
  end

  def test_field_name_without_headers
    force_quotes = ["a", "c"]
    error = assert_raise(ArgumentError) do
      generate_line(["1", "2", "3"],
                    force_quotes: force_quotes)
    end
    assert_equal(":headers is required when you use field name " +
                 "in :force_quotes: " +
                 "#{force_quotes.first.inspect}: #{force_quotes.inspect}",
                 error.message)
  end

  def test_field_index
    assert_equal(%Q["1",2,"3"#{$INPUT_RECORD_SEPARATOR}],
                 generate_line(["1", "2", "3"],
                               force_quotes: [0, 2]))
  end

  def test_field_unknown
    force_quotes = [1.1]
    error = assert_raise(ArgumentError) do
      generate_line(["1", "2", "3"],
                    force_quotes: force_quotes)
    end
    assert_equal(":force_quotes element must be field index or field name: " +
                 "#{force_quotes.first.inspect}: #{force_quotes.inspect}",
                 error.message)
  end
end

class TestCSVWriteForceQuotesGenerateLine < Test::Unit::TestCase
  include TestCSVWriteForceQuotes
  extend DifferentOFS

  def generate_line(row, **kwargs)
    CSV.generate_line(row, **kwargs)
  end
end

class TestCSVWriteForceQuotesGenerate < Test::Unit::TestCase
  include TestCSVWriteForceQuotes
  extend DifferentOFS

  def generate_line(row, **kwargs)
    CSV.generate(**kwargs) do |csv|
      csv << row
    end
  end
end
