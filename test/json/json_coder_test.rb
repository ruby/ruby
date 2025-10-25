#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_helper'

class JSONCoderTest < Test::Unit::TestCase
  def test_json_coder_with_proc
    coder = JSON::Coder.new do |object|
      "[Object object]"
    end
    assert_equal %(["[Object object]"]), coder.dump([Object.new])
  end

  def test_json_coder_with_proc_with_unsupported_value
    coder = JSON::Coder.new do |object, is_key|
      assert_equal false, is_key
      Object.new
    end
    assert_raise(JSON::GeneratorError) { coder.dump([Object.new]) }
  end

  def test_json_coder_hash_key
    obj = Object.new
    coder = JSON::Coder.new do |obj, is_key|
      assert_equal true, is_key
      obj.to_s
    end
    assert_equal %({#{obj.to_s.inspect}:1}), coder.dump({ obj => 1 })

    coder = JSON::Coder.new { 42 }
    error = assert_raise JSON::GeneratorError do
      coder.dump({ obj => 1 })
    end
    assert_equal "Integer not allowed as object key in JSON", error.message
  end

  def test_json_coder_options
    coder = JSON::Coder.new(array_nl: "\n") do |object|
      42
    end

    assert_equal "[\n42\n]", coder.dump([Object.new])
  end

  def test_json_coder_load
    coder = JSON::Coder.new
    assert_equal [1,2,3], coder.load("[1,2,3]")
  end

  def test_json_coder_load_options
    coder = JSON::Coder.new(symbolize_names: true)
    assert_equal({a: 1}, coder.load('{"a":1}'))
  end

  def test_json_coder_dump_NaN_or_Infinity
    coder = JSON::Coder.new { |o| o.inspect }
    assert_equal "NaN", coder.load(coder.dump(Float::NAN))
    assert_equal "Infinity", coder.load(coder.dump(Float::INFINITY))
    assert_equal "-Infinity", coder.load(coder.dump(-Float::INFINITY))
  end

  def test_json_coder_dump_NaN_or_Infinity_loop
    coder = JSON::Coder.new { |o| o.itself }
    error = assert_raise JSON::GeneratorError do
      coder.dump(Float::NAN)
    end
    assert_include error.message, "NaN not allowed in JSON"
  end

  def test_nesting_recovery
    coder = JSON::Coder.new
    ary = []
    ary << ary
    assert_raise JSON::NestingError do
      coder.dump(ary)
    end
    assert_equal '{"a":1}', coder.dump({ a: 1 })
  end
end
