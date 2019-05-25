# frozen_string_literal: false

require "test/unit"
require "rexml/document"
require "rexml/functions"

module REXMLTests
  class TestFunctionsBoolean < Test::Unit::TestCase
    def setup
      REXML::Functions.context = nil
    end

    def test_true
      assert_equal(true, REXML::Functions.boolean(true))
    end

    def test_false
      assert_equal(false, REXML::Functions.boolean(false))
    end

    def test_integer_true
      assert_equal(true, REXML::Functions.boolean(1))
    end

    def test_integer_positive_zero
      assert_equal(false, REXML::Functions.boolean(0))
    end

    def test_integer_negative_zero
      assert_equal(false, REXML::Functions.boolean(-0))
    end

    def test_float_true
      assert_equal(true, REXML::Functions.boolean(1.1))
    end

    def test_float_positive_zero
      assert_equal(false, REXML::Functions.boolean(-0.0))
    end

    def test_float_negative_zero
      assert_equal(false, REXML::Functions.boolean(-0.0))
    end

    def test_float_nan
      assert_equal(false, REXML::Functions.boolean(Float::NAN))
    end

    def test_string_true
      assert_equal(true, REXML::Functions.boolean("content"))
    end

    def test_string_empty
      assert_equal(false, REXML::Functions.boolean(""))
    end

    def test_node_set_true
      root = REXML::Document.new("<root/>").root
      assert_equal(true, REXML::Functions.boolean([root]))
    end

    def test_node_set_empty
      assert_equal(false, REXML::Functions.boolean([]))
    end

    def test_nil
      assert_equal(false, REXML::Functions.boolean(nil))
    end

    def test_context
      REXML::Functions.context = {node: true}
      assert_equal(true, REXML::Functions.boolean())
    end
  end
end
