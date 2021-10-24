# frozen_string_literal: false
require 'test/unit'
require "-test-/string"
require "tempfile"

class Test_StringNormalize < Test::Unit::TestCase
=begin
  def test_normalize_all
    exclude = [
      #0x340, 0x341, 0x343, 0x344
    ]
    (0x0080..0xFFFD).each do |n|
      next if 0xD800 <= n && n <= 0xDFFF
      next if exclude.include? n
      code = n.to_s(16)
      Tempfile.create("#{code}-#{n.chr(Encoding::UTF_8)}-") do |tempfile|
        ary = Dir.glob(File.expand_path("../#{code}-*", tempfile.path))
        assert_equal 1, ary.size
        result = ary[0]
        rn = result[/\/\h+-(.+?)-/, 1]
        #assert_equal tempfile.path, result, "#{rn.dump} is not U+#{n.to_s(16)}"
        r2 = Bug::String.new(result ).normalize_ospath
        rn2 = r2[/\/\h+-(.+?)-/, 1]
        if tempfile.path == result
          if tempfile.path == r2
          else
            puts "U+#{n.to_s(16)} shouldn't be r2#{rn2.dump}"
          end
        else
          if tempfile.path == r2
            # puts "U+#{n.to_s(16)} shouldn't be r#{rn.dump}"
          elsif result == r2
            puts "U+#{n.to_s(16)} shouldn't be #{rn.dump}"
          else
            puts "U+#{n.to_s(16)} shouldn't be r#{rn.dump} r2#{rn2.dump}"
          end
        end
      end
    end
  end
=end

  def test_normalize
    %[
      \u304C \u304B\u3099
      \u3077 \u3075\u309A
      \u308F\u3099 \u308F\u3099
      \u30F4 \u30A6\u3099
      \u30DD \u30DB\u309A
      \u30AB\u303A \u30AB\u303A
      \u00C1 A\u0301
      B\u030A B\u030A
      \u0386 \u0391\u0301
      \u03D3 \u03D2\u0301
      \u0401 \u0415\u0308
      \u2260 =\u0338
      \u{c548} \u{110b}\u{1161}\u{11ab}
    ].scan(/(\S+)\s+(\S+)/) do |expected, src|
      result = Bug::String.new(src).normalize_ospath
      assert_equal expected, result,
        "#{expected.dump} is expected but #{src.dump}"
    end
  end

  def test_not_normalize_kc
    %W[
      \u2460
      \u2162
      \u3349
      \u33A1
      \u337B
      \u2116
      \u33CD
      \u2121
      \u32A4
      \u3231
    ].each do |src|
      result = Bug::String.new(src).normalize_ospath
      assert_equal src, result,
        "#{src.dump} is expected not to be normalized, but #{result.dump}"
    end
  end

  def test_dont_normalize_hfsplus
    %W[
      \u2190\u0338
      \u219A
      \u212B
      \uF90A
      \uF9F4
      \uF961 \uF9DB
      \uF96F \uF3AA
      \uF915 \uF95C \uF9BF
      \uFA0C
      \uFA10
      \uFA19
      \uFA26
    ].each do |src|
      result = Bug::String.new(src).normalize_ospath
      assert_equal src, result,
        "#{src.dump} is expected not to be normalized, but #{result.dump}"
    end
  end

  def test_invalid_sequence
    assert_separately(%w[-r-test-/string], <<-'end;')
      assert_equal("\u{fffd}", Bug::String.new("\xff").normalize_ospath)
    end;
  end
end if Bug::String.method_defined?(:normalize_ospath)
