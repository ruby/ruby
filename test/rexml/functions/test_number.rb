# frozen_string_literal: false

require "test/unit"
require "rexml/document"
require "rexml/functions"

module REXMLTests
  class TestFunctionsNumber < Test::Unit::TestCase
    def setup
      REXML::Functions.context = nil
    end

    def test_true
      assert_equal(1, REXML::Functions.number(true))
    end

    def test_false
      assert_equal(0, REXML::Functions.number(false))
    end

    def test_numeric
      assert_equal(29, REXML::Functions.number(29))
    end

    def test_string_integer
      assert_equal(100, REXML::Functions.number("100"))
    end

    def test_string_float
      assert_equal(-9.13, REXML::Functions.number("-9.13"))
    end

    def test_node_set
      root = REXML::Document.new("<root>100</root>").root
      assert_equal(100, REXML::Functions.number([root]))
    end
  end
end
