# frozen_string_literal: false
require_relative 'test_helper'

class JSONEncodingTest < Test::Unit::TestCase
  include JSON

  def setup
    @utf_8      = '"© ≠ €!"'
    @ascii_8bit = @utf_8.dup.force_encoding('ascii-8bit')
    @parsed     = "© ≠ €!"
    @generated  = '"\u00a9 \u2260 \u20ac!"'
    if String.method_defined?(:encode)
      @utf_16_data = @parsed.encode('utf-16be', 'utf-8')
      @utf_16be = @utf_8.encode('utf-16be', 'utf-8')
      @utf_16le = @utf_8.encode('utf-16le', 'utf-8')
      @utf_32be = @utf_8.encode('utf-32be', 'utf-8')
      @utf_32le = @utf_8.encode('utf-32le', 'utf-8')
    else
      require 'iconv'
      @utf_16_data, = Iconv.iconv('utf-16be', 'utf-8', @parsed)
      @utf_16be, = Iconv.iconv('utf-16be', 'utf-8', @utf_8)
      @utf_16le, = Iconv.iconv('utf-16le', 'utf-8', @utf_8)
      @utf_32be, = Iconv.iconv('utf-32be', 'utf-8', @utf_8)
      @utf_32le, = Iconv.iconv('utf-32le', 'utf-8', @utf_8)
    end
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
    assert_equal @generated, JSON.generate(@parsed, :ascii_only => true)
    assert_equal @generated, JSON.generate(@utf_16_data, :ascii_only => true)
  end

  def test_unicode
    assert_equal '""', ''.to_json
    assert_equal '"\\b"', "\b".to_json
    assert_equal '"\u0001"', 0x1.chr.to_json
    assert_equal '"\u001f"', 0x1f.chr.to_json
    assert_equal '" "', ' '.to_json
    assert_equal "\"#{0x7f.chr}\"", 0x7f.chr.to_json
    utf8 = [ "© ≠ €! \01" ]
    json = '["© ≠ €! \u0001"]'
    assert_equal json, utf8.to_json(:ascii_only => false)
    assert_equal utf8, parse(json)
    json = '["\u00a9 \u2260 \u20ac! \u0001"]'
    assert_equal json, utf8.to_json(:ascii_only => true)
    assert_equal utf8, parse(json)
    utf8 = ["\343\201\202\343\201\204\343\201\206\343\201\210\343\201\212"]
    json = "[\"\343\201\202\343\201\204\343\201\206\343\201\210\343\201\212\"]"
    assert_equal utf8, parse(json)
    assert_equal json, utf8.to_json(:ascii_only => false)
    utf8 = ["\343\201\202\343\201\204\343\201\206\343\201\210\343\201\212"]
    assert_equal utf8, parse(json)
    json = "[\"\\u3042\\u3044\\u3046\\u3048\\u304a\"]"
    assert_equal json, utf8.to_json(:ascii_only => true)
    assert_equal utf8, parse(json)
    utf8 = ['საქართველო']
    json = '["საქართველო"]'
    assert_equal json, utf8.to_json(:ascii_only => false)
    json = "[\"\\u10e1\\u10d0\\u10e5\\u10d0\\u10e0\\u10d7\\u10d5\\u10d4\\u10da\\u10dd\"]"
    assert_equal json, utf8.to_json(:ascii_only => true)
    assert_equal utf8, parse(json)
    assert_equal '["Ã"]', generate(["Ã"], :ascii_only => false)
    assert_equal '["\\u00c3"]', generate(["Ã"], :ascii_only => true)
    assert_equal ["€"], parse('["\u20ac"]')
    utf8 = ["\xf0\xa0\x80\x81"]
    json = "[\"\xf0\xa0\x80\x81\"]"
    assert_equal json, generate(utf8, :ascii_only => false)
    assert_equal utf8, parse(json)
    json = '["\ud840\udc01"]'
    assert_equal json, generate(utf8, :ascii_only => true)
    assert_equal utf8, parse(json)
    assert_raise(JSON::ParserError) { parse('"\u"') }
    assert_raise(JSON::ParserError) { parse('"\ud800"') }
  end

  def test_chars
    (0..0x7f).each do |i|
      json = '["\u%04x"]' % i
      i = i.chr
      assert_equal i, parse(json).first[0]
      if i == ?\b
        generated = generate(["" << i])
        assert '["\b"]' == generated || '["\10"]' == generated
      elsif [?\n, ?\r, ?\t, ?\f].include?(i)
        assert_equal '[' << ('' << i).dump << ']', generate(["" << i])
      elsif i.chr < 0x20.chr
        assert_equal json, generate(["" << i])
      end
    end
    assert_raise(JSON::GeneratorError) do
      generate(["\x80"], :ascii_only => true)
    end
    assert_equal "\302\200", parse('["\u0080"]').first
  end
end
