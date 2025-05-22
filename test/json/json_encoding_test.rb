# frozen_string_literal: true

require_relative 'test_helper'

class JSONEncodingTest < Test::Unit::TestCase
  include JSON

  def setup
    @utf_8      = '"© ≠ €!"'
    @ascii_8bit = @utf_8.b
    @parsed     = "© ≠ €!"
    @generated  = '"\u00a9 \u2260 \u20ac!"'
    @utf_16_data = @parsed.encode(Encoding::UTF_16BE, Encoding::UTF_8)
    @utf_16be = @utf_8.encode(Encoding::UTF_16BE, Encoding::UTF_8)
    @utf_16le = @utf_8.encode(Encoding::UTF_16LE, Encoding::UTF_8)
    @utf_32be = @utf_8.encode(Encoding::UTF_32BE, Encoding::UTF_8)
    @utf_32le = @utf_8.encode(Encoding::UTF_32LE, Encoding::UTF_8)
  end

  def test_parse
    assert_equal @parsed, JSON.parse(@ascii_8bit)
    assert_equal @parsed, JSON.parse(@utf_8)
    assert_equal @parsed, JSON.parse(@utf_16be)
    assert_equal @parsed, JSON.parse(@utf_16le)
    assert_equal @parsed, JSON.parse(@utf_32be)
    assert_equal @parsed, JSON.parse(@utf_32le)
  end

  def test_generate
    assert_equal @generated, JSON.generate(@parsed, ascii_only: true)
    assert_equal @generated, JSON.generate(@utf_16_data, ascii_only: true)
  end

  def test_unicode
    assert_equal '""', ''.to_json
    assert_equal '"\\b"', "\b".to_json
    assert_equal '"\u0001"', 0x1.chr.to_json
    assert_equal '"\u001f"', 0x1f.chr.to_json
    assert_equal '" "', ' '.to_json
    assert_equal "\"#{0x7f.chr}\"", 0x7f.chr.to_json
    utf8 = ["© ≠ €! \01"]
    json = '["© ≠ €! \u0001"]'
    assert_equal json, utf8.to_json(ascii_only: false)
    assert_equal utf8, parse(json)
    json = '["\u00a9 \u2260 \u20ac! \u0001"]'
    assert_equal json, utf8.to_json(ascii_only: true)
    assert_equal utf8, parse(json)
    utf8 = ["\343\201\202\343\201\204\343\201\206\343\201\210\343\201\212"]
    json = "[\"\343\201\202\343\201\204\343\201\206\343\201\210\343\201\212\"]"
    assert_equal utf8, parse(json)
    assert_equal json, utf8.to_json(ascii_only: false)
    utf8 = ["\343\201\202\343\201\204\343\201\206\343\201\210\343\201\212"]
    assert_equal utf8, parse(json)
    json = "[\"\\u3042\\u3044\\u3046\\u3048\\u304a\"]"
    assert_equal json, utf8.to_json(ascii_only: true)
    assert_equal utf8, parse(json)
    utf8 = ['საქართველო']
    json = '["საქართველო"]'
    assert_equal json, utf8.to_json(ascii_only: false)
    json = "[\"\\u10e1\\u10d0\\u10e5\\u10d0\\u10e0\\u10d7\\u10d5\\u10d4\\u10da\\u10dd\"]"
    assert_equal json, utf8.to_json(ascii_only: true)
    assert_equal utf8, parse(json)
    assert_equal '["Ã"]', generate(["Ã"], ascii_only: false)
    assert_equal '["\\u00c3"]', generate(["Ã"], ascii_only: true)
    assert_equal ["€"], parse('["\u20ac"]')
    utf8 = ["\xf0\xa0\x80\x81"]
    json = "[\"\xf0\xa0\x80\x81\"]"
    assert_equal json, generate(utf8, ascii_only: false)
    assert_equal utf8, parse(json)
    json = '["\ud840\udc01"]'
    assert_equal json, generate(utf8, ascii_only: true)
    assert_equal utf8, parse(json)
    assert_raise(JSON::ParserError) { parse('"\u"') }
    assert_raise(JSON::ParserError) { parse('"\ud800"') }
  end

  def test_chars
    (0..0x7f).each do |i|
      json = '"\u%04x"' % i
      i = i.chr
      assert_equal i, parse(json)[0]
      if i == "\b"
        generated = generate(i)
        assert ['"\b"', '"\10"'].include?(generated)
      elsif ["\n", "\r", "\t", "\f"].include?(i)
        assert_equal i.dump, generate(i)
      elsif i.chr < 0x20.chr
        assert_equal json, generate(i)
      end
    end
    assert_raise(JSON::GeneratorError) do
      generate(["\x80"], ascii_only: true)
    end
    assert_equal "\302\200", parse('"\u0080"')
  end

  def test_deeply_nested_structures
    # Test for deeply nested arrays
    nesting_level = 100
    deeply_nested = []
    current = deeply_nested

    (nesting_level - 1).times do
      current << []
      current = current[0]
    end

    json = generate(deeply_nested)
    assert_equal deeply_nested, parse(json)

    # Test for deeply nested objects/hashes
    deeply_nested_hash = {}
    current_hash = deeply_nested_hash

    (nesting_level - 1).times do |i|
      current_hash["key#{i}"] = {}
      current_hash = current_hash["key#{i}"]
    end

    json = generate(deeply_nested_hash)
    assert_equal deeply_nested_hash, parse(json)
  end

  def test_very_large_json_strings
    # Create a large array with repeated elements
    large_array = Array.new(10_000) { |i| "item#{i}" }

    json = generate(large_array)
    parsed = parse(json)

    assert_equal large_array.size, parsed.size
    assert_equal large_array.first, parsed.first
    assert_equal large_array.last, parsed.last

    # Create a large hash
    large_hash = {}
    10_000.times { |i| large_hash["key#{i}"] = "value#{i}" }

    json = generate(large_hash)
    parsed = parse(json)

    assert_equal large_hash.size, parsed.size
    assert_equal large_hash["key0"], parsed["key0"]
    assert_equal large_hash["key9999"], parsed["key9999"]
  end

  def test_invalid_utf8_sequences
    # Create strings with invalid UTF-8 sequences
    invalid_utf8 = "\xFF\xFF"

    # Test that generating JSON with invalid UTF-8 raises an error
    # Different JSON implementations may handle this differently,
    # so we'll check if any exception is raised
    begin
      generate(invalid_utf8)
      raise "Expected an exception when generating JSON with invalid UTF8"
    rescue StandardError => e
      assert true
      assert_match(%r{source sequence is illegal/malformed utf-8}, e.message)
    end
  end

  def test_surrogate_pair_handling
    # Test valid surrogate pairs
    assert_equal "\u{10000}", parse('"\ud800\udc00"')
    assert_equal "\u{10FFFF}", parse('"\udbff\udfff"')

    # The existing test already checks for orphaned high surrogate
    assert_raise(JSON::ParserError) { parse('"\ud800"') }

    # Test generating surrogate pairs
    utf8_string = "\u{10437}"
    generated = generate(utf8_string, ascii_only: true)
    assert_match(/\\ud801\\udc37/, generated)
  end

  def test_json_escaping_edge_cases
    # Test escaping forward slashes
    assert_equal "/", parse('"\/"')

    # Test escaping backslashes
    assert_equal "\\", parse('"\\\\"')

    # Test escaping quotes
    assert_equal '"', parse('"\\""')

    # Multiple escapes in sequence - different JSON parsers might handle escaped forward slashes differently
    # Some parsers preserve the escaping, others don't
    escaped_result = parse('"\\\\\\"\\/"')
    assert_match(/\\"/, escaped_result)
    assert_match(%r{/}, escaped_result)

    # Generate string with all special characters
    special_chars = "\b\f\n\r\t\"\\"
    escaped_json = generate(special_chars)
    assert_equal special_chars, parse(escaped_json)
  end

  def test_empty_objects_and_arrays
    # Test empty objects with different encodings
    assert_equal({}, parse('{}'))
    assert_equal({}, parse('{}'.encode(Encoding::UTF_16BE)))
    assert_equal({}, parse('{}'.encode(Encoding::UTF_16LE)))
    assert_equal({}, parse('{}'.encode(Encoding::UTF_32BE)))
    assert_equal({}, parse('{}'.encode(Encoding::UTF_32LE)))

    # Test empty arrays with different encodings
    assert_equal([], parse('[]'))
    assert_equal([], parse('[]'.encode(Encoding::UTF_16BE)))
    assert_equal([], parse('[]'.encode(Encoding::UTF_16LE)))
    assert_equal([], parse('[]'.encode(Encoding::UTF_32BE)))
    assert_equal([], parse('[]'.encode(Encoding::UTF_32LE)))

    # Test generating empty objects and arrays
    assert_equal '{}', generate({})
    assert_equal '[]', generate([])
  end

  def test_null_character_handling
    # Test parsing null character
    assert_equal "\u0000", parse('"\u0000"')

    # Test generating null character
    string_with_null = "\u0000"
    generated = generate(string_with_null)
    assert_equal '"\u0000"', generated

    # Test null characters in middle of string
    mixed_string = "before\u0000after"
    generated = generate(mixed_string)
    assert_equal mixed_string, parse(generated)
  end

  def test_whitespace_handling
    # Test parsing with various whitespace patterns
    assert_equal({}, parse(' { } '))
    assert_equal({}, parse("{\r\n}"))
    assert_equal([], parse(" [ \n ] "))
    assert_equal(["a", "b"], parse(" [ \n\"a\",\r\n  \"b\"\n ] "))
    assert_equal({ "a" => "b" }, parse(" { \n\"a\" \r\n: \t\"b\"\n } "))

    # Test with excessive whitespace
    excessive_whitespace = " \n\r\t" * 10 + "{}" + " \n\r\t" * 10
    assert_equal({}, parse(excessive_whitespace))

    # Mixed whitespace in keys and values
    mixed_json = '{"a \n b":"c \r\n d"}'
    assert_equal({ "a \n b" => "c \r\n d" }, parse(mixed_json))
  end

  def test_control_character_handling
    # Test all control characters (U+0000 to U+001F)
    (0..0x1F).each do |i|
      # Skip already tested ones
      next if [0x08, 0x0A, 0x0D, 0x0C, 0x09].include?(i)

      control_char = i.chr('UTF-8')
      escaped_json = '"' + "\\u%04x" % i + '"'
      assert_equal control_char, parse(escaped_json)

      # Check that the character is properly escaped when generating
      assert_match(/\\u00[0-1][0-9a-f]/, generate(control_char))
    end

    # Test string with multiple control characters
    control_str = "\u0001\u0002\u0003\u0004"
    generated = generate(control_str)
    assert_equal control_str, parse(generated)
    assert_match(/\\u0001\\u0002\\u0003\\u0004/, generated)
  end
end
