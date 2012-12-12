#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'test/unit'
require File.join(File.dirname(__FILE__), 'setup_variant')
class TestJSONGenericObject < Test::Unit::TestCase
  include JSON

  def setup
    @go = GenericObject[ :a => 1, :b => 2 ]
  end

  def test_attributes
    assert_equal 1, @go.a
    assert_equal 1, @go[:a]
    assert_equal 2, @go.b
    assert_equal 2, @go[:b]
    assert_nil @go.c
    assert_nil @go[:c]
  end

  def test_generate_json
    assert_equal @go, JSON(JSON(@go))
  end

  def test_parse_json
    assert_equal @go, l = JSON('{ "json_class": "JSON::GenericObject", "a": 1, "b": 2 }')
    assert_equal 1, l.a
    assert_equal @go, l = JSON('{ "a": 1, "b": 2 }', :object_class => GenericObject)
    assert_equal 1, l.a
    assert_equal GenericObject[:a => GenericObject[:b => 2]],
      l = JSON('{ "a": { "b": 2 } }', :object_class => GenericObject)
    assert_equal 2, l.a.b
  end
end
