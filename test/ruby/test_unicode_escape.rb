# -*- coding: utf-8 -*-

require 'test/unit'

class TestUnicodeEscape < Test::Unit::TestCase
  def test_basic
    assert_equal('Matz - 松本行弘',
      "Matz - \u677E\u672C\u884C\u5F18")
    assert_equal('Matz - まつもと ゆきひろ',
      "Matz - \u307E\u3064\u3082\u3068 \u3086\u304D\u3072\u308D")
    assert_equal('Matz - まつもと ゆきひろ',
                 "Matz - \u{307E}\u{3064}\u{3082}\u{3068} \u{3086}\u{304D}\u{3072}\u{308D}")
    assert_equal('Matz - まつもと ゆきひろ',
                 "Matz - \u{307E 3064 3082 3068 20 3086 304D 3072 308D}")
    assert_equal("Aoyama Gakuin University - \xE9\x9D\x92\xE5\xB1\xB1\xE5\xAD\xA6\xE9\x99\xA2\xE5\xA4\xA7\xE5\xAD\xA6",
      "Aoyama Gakuin University - \u9752\u5C71\u5B66\u9662\u5927\u5B66")
    assert_equal('Aoyama Gakuin University - 青山学院大学',
      "Aoyama Gakuin University - \u9752\u5C71\u5B66\u9662\u5927\u5B66")
    assert_equal('青山学院大学', "\u9752\u5C71\u5B66\u9662\u5927\u5B66")
    assert_equal("Martin D\xC3\xBCrst", "Martin D\u00FCrst")
    assert_equal('Martin Dürst', "Martin D\u00FCrst")
    assert_equal('ü', "\u00FC")
    assert_equal("Martin D\xC3\xBCrst", "Martin D\u{FC}rst")
    assert_equal('Martin Dürst', "Martin D\u{FC}rst")
    assert_equal('ü', "\u{FC}")
    assert_equal('ü', %Q|\u{FC}|)
    assert_equal('ü', %W{\u{FC}}[0])

    # \u escapes in here documents
    assert_equal('Matz - まつもと ゆきひろ', <<EOS.chop)
Matz - \u307E\u3064\u3082\u3068 \u3086\u304D\u3072\u308D
EOS

    assert_equal('Matz - まつもと ゆきひろ', <<"EOS".chop)
Matz - \u{307E 3064 3082 3068} \u{3086 304D 3072 308D}
EOS
    assert_not_equal('Matz - まつもと ゆきひろ', <<'EOS'.chop)
Matz - \u{307E 3064 3082 3068} \u{3086 304D 3072 308D}
EOS

    # single-quoted things don't expand \u
    assert_not_equal('ü', '\u{FC}')
    assert_not_equal('ü', %q|\u{FC}|)
    assert_not_equal('ü', %w{\u{FC}}[0])
    assert_equal('\u00fc', "\\" + "u00fc")

    # \u in %x strings
    assert_equal(`echo "\u0041"`.chop, "A")
    assert_equal(%x{echo "\u0041"}.chop, "A")
    assert_equal(`echo "\u{FC}"`.force_encoding("utf-8"), "ü\n")

    # \u in quoted symbols
    assert_equal(:A, :"\u0041")
    assert_equal(:a, :"\u0061")
    assert_equal(:ま, :ま)
    assert_equal(:ü, :ü)
    assert_equal(:"\u{41}", :"\u0041")
    assert_equal(:ü, :"\u{fc}")

    # the NUL character is not allowed in symbols
    assert_raise(SyntaxError) { eval %q(:"\u{0}")} 
    assert_raise(SyntaxError) { eval %q(:"\u0000")}
    assert_raise(SyntaxError) { eval %q(:"\u{fc 0 0041}")} 
    assert_raise(SyntaxError) { eval %q(:"\x00")} 
    assert_raise(SyntaxError) { eval %q(:"\0")}
  end

  def test_regexp

    # Compare regexps to regexps
    assert_equal(/Yukihiro Matsumoto - 松本行弘/,
      /Yukihiro Matsumoto - \u677E\u672C\u884C\u5F18/)
    assert_equal(/Yukihiro Matsumoto - 松本行弘/,
                 /Yukihiro Matsumoto - \u{677E 672C 884C 5F18}/)
    assert_equal(/Matz - まつもと ゆきひろ/,
      /Matz - \u307E\u3064\u3082\u3068 \u3086\u304D\u3072\u308D/)
    assert_equal(/Aoyama Gakuin University - 青山学院大学/,
      /Aoyama Gakuin University - \u9752\u5C71\u5B66\u9662\u5927\u5B66/)
    assert_equal(/青山学院大学/, /\u9752\u5C71\u5B66\u9662\u5927\u5B66/)
    assert_equal(/Martin Dürst/, /Martin D\u00FCrst/)
    assert_equal(/ü/, /\u00FC/)
    assert_equal(/Martin Dürst/, /Martin D\u{FC}rst/)
    assert_equal(/ü/, /\u{FC}/)
    assert_equal(/ü/, %r{\u{FC}})
    assert_equal(/ü/i, %r{\u00FC}i)

    # match strings to regexps
    assert_equal("Yukihiro Matsumoto - 松本行弘" =~ /Yukihiro Matsumoto - \u677E\u672C\u884C\u5F18/, 0)
    assert_equal("Yukihiro Matsumoto - \u677E\u672C\u884C\u5F18" =~ /Yukihiro Matsumoto - \u677E\u672C\u884C/, 0)
    assert_equal("Yukihiro Matsumoto - 松本行弘" =~            /Yukihiro Matsumoto - \u{677E 672C 884C 5F18}/, 0)
    assert_equal(%Q{Yukihiro Matsumoto - \u{677E 672C 884C 5F18}} =~ /Yukihiro Matsumoto - \u{677E 672C 884C 5F18}/, 0)
    assert_equal("Matz - まつもと ゆきひろ" =~ /Matz - \u307E\u3064\u3082\u3068 \u3086\u304D\u3072\u308D/, 0)
    assert_equal("Aoyama Gakuin University - 青山学院大学" =~ /Aoyama Gakuin University - \u9752\u5C71\u5B66\u9662\u5927\u5B66/, 0)
    assert_equal("青山学院大学" =~ /\u9752\u5C71\u5B66\u9662\u5927\u5B66/, 0)
    assert_equal("Martin Dürst" =~ /Martin D\u00FCrst/, 0)
    assert_equal("ü" =~ /\u00FC/, 0)
    assert_equal("Martin Dürst" =~ /Martin D\u{FC}rst/, 0)
    assert_equal("ü" =~ %r{\u{FC}}, 0)
    assert_equal("ü" =~ %r{\u00FC}i, 0)

    # Flip order of the two operands
    assert_equal(/Martin D\u00FCrst/ =~ "Martin Dürst", 0)
    assert_equal(/\u00FC/ =~ "testü", 4)
    assert_equal(/Martin D\u{FC}rst/ =~ "fooMartin Dürstbar", 3)
    assert_equal(%r{\u{FC}} =~ "fooübar", 3)

    # Put \u in strings, literal character in regexp
    assert_equal("Martin D\u00FCrst" =~ /Martin Dürst/, 0)
    assert_equal("test\u00FC" =~ /ü/, 4)
    assert_equal("fooMartin D\u{FC}rstbar" =~ /Martin Dürst/, 3)
    assert_equal(%Q{foo\u{FC}bar} =~ %r<ü>, 3)
  end
  
  def test_syntax_variants
    # all hex digits
    assert_equal("\xC4\xA3\xE4\x95\xA7\xE8\xA6\xAB\xEC\xB7\xAF", "\u0123\u4567\u89AB\uCDEF")
    assert_equal("\xC4\xA3\xE4\x95\xA7\xE8\xA6\xAB\xEC\xB7\xAF", "\u0123\u4567\u89AB\uCDEF")
    assert_equal("\xC4\xA3\xE4\x95\xA7\xE8\xA6\xAB\xEC\xB7\xAF", "\u0123\u4567\u89ab\ucdef")
    assert_equal("\xC4\xA3\xE4\x95\xA7\xE8\xA6\xAB\xEC\xB7\xAF", "\u0123\u4567\u89ab\ucdef")
    assert_equal("\xC4\xA3\xE4\x95\xA7\xE8\xA6\xAB\xEC\xB7\xAF", "\u0123\u4567\u89aB\uCdEf")
    assert_equal("\xC4\xA3\xE4\x95\xA7\xE8\xA6\xAB\xEC\xB7\xAF", "\u0123\u4567\u89aB\ucDEF")
  end
  
  def test_fulton
    # examples from Hal Fulton's book (second edition), chapter 4
    # precomposed e'pe'e
    assert_equal('épée', "\u00E9\u0070\u00E9\u0065")
    assert_equal('épée', "\u00E9p\u00E9e")
    assert_equal("\xC3\xA9\x70\xC3\xA9\x65", "\u00E9\u0070\u00E9\u0065")
    assert_equal("\xC3\xA9\x70\xC3\xA9\x65", "\u00E9p\u00E9e")
    # decomposed e'pe'e
    assert_equal('épée', "\u0065\u0301\u0070\u0065\u0301\u0065")
    assert_equal('épée', "e\u0301pe\u0301e")
    assert_equal("\x65\xCC\x81\x70\x65\xCC\x81\x65", "\u0065\u0301\u0070\u0065\u0301\u0065")
    assert_equal("\x65\xCC\x81\x70\x65\xCC\x81\x65", "e\u0301pe\u0301e")
    # combinations of NFC/D, NFKC/D
    assert_equal('öffnen', "\u00F6\u0066\u0066\u006E\u0065\u006E")
    assert_equal("\xC3\xB6ffnen", "\u00F6\u0066\u0066\u006E\u0065\u006E")
    assert_equal('öffnen', "\u00F6ffnen")
    assert_equal("\xC3\xB6ffnen", "\u00F6ffnen")
    assert_equal('öffnen', "\u006F\u0308\u0066\u0066\u006E\u0065\u006E")
    assert_equal("\x6F\xCC\x88ffnen", "\u006F\u0308\u0066\u0066\u006E\u0065\u006E")
    assert_equal('öffnen', "o\u0308ffnen")
    assert_equal("\x6F\xCC\x88ffnen", "o\u0308ffnen")
    assert_equal('öﬀnen', "\u00F6\uFB00\u006E\u0065\u006E")
    assert_equal("\xC3\xB6\xEF\xAC\x80nen", "\u00F6\uFB00\u006E\u0065\u006E")
    assert_equal('öﬀnen', "\u00F6\uFB00nen")
    assert_equal("\xC3\xB6\xEF\xAC\x80nen", "\u00F6\uFB00nen")
    assert_equal('öﬀnen', "\u006F\u0308\uFB00\u006E\u0065\u006E")
    assert_equal("\x6F\xCC\x88\xEF\xAC\x80nen", "\u006F\u0308\uFB00\u006E\u0065\u006E")
    assert_equal('öﬀnen', "o\u0308\uFB00nen")
    assert_equal("\x6F\xCC\x88\xEF\xAC\x80nen", "o\u0308\uFB00nen")
    # German sharp s (sz)
    assert_equal('Straße', "\u0053\u0074\u0072\u0061\u00DF\u0065")
    assert_equal("\x53\x74\x72\x61\xC3\x9F\x65", "\u0053\u0074\u0072\u0061\u00DF\u0065")
    assert_equal('Straße', "Stra\u00DFe")
    assert_equal("\x53\x74\x72\x61\xC3\x9F\x65", "Stra\u00DFe")
    assert_equal('Straße', "\u{53}\u{74}\u{72}\u{61}\u{DF}\u{65}")
    assert_equal("\x53\x74\x72\x61\xC3\x9F\x65", "\u{53}\u{74}\u{72}\u{61}\u{DF}\u{65}")
    assert_equal("\x53\x74\x72\x61\xC3\x9F\x65", "\u{53 74 72 61 DF 65}")
    assert_equal('Straße', "Stra\u{DF}e")
    assert_equal("\x53\x74\x72\x61\xC3\x9F\x65", "Stra\u{DF}e")
  end
  
  def test_edge_cases
    # start and end of each outer plane
    assert_equal("\xF4\x8F\xBF\xBF", "\u{10FFFF}")
    assert_equal("\xF4\x80\x80\x80", "\u{100000}")
    assert_equal("\xF3\xBF\xBF\xBF", "\u{FFFFF}")
    assert_equal("\xF3\xB0\x80\x80", "\u{F0000}")
    assert_equal("\xF3\xAF\xBF\xBF", "\u{EFFFF}")
    assert_equal("\xF3\xA0\x80\x80", "\u{E0000}")
    assert_equal("\xF3\x9F\xBF\xBF", "\u{DFFFF}")
    assert_equal("\xF3\x90\x80\x80", "\u{D0000}")
    assert_equal("\xF3\x8F\xBF\xBF", "\u{CFFFF}")
    assert_equal("\xF3\x80\x80\x80", "\u{C0000}")
    assert_equal("\xF2\xBF\xBF\xBF", "\u{BFFFF}")
    assert_equal("\xF2\xB0\x80\x80", "\u{B0000}")
    assert_equal("\xF2\xAF\xBF\xBF", "\u{AFFFF}")
    assert_equal("\xF2\xA0\x80\x80", "\u{A0000}")
    assert_equal("\xF2\x9F\xBF\xBF", "\u{9FFFF}")
    assert_equal("\xF2\x90\x80\x80", "\u{90000}")
    assert_equal("\xF2\x8F\xBF\xBF", "\u{8FFFF}")
    assert_equal("\xF2\x80\x80\x80", "\u{80000}")
    assert_equal("\xF1\xBF\xBF\xBF", "\u{7FFFF}")
    assert_equal("\xF1\xB0\x80\x80", "\u{70000}")
    assert_equal("\xF1\xAF\xBF\xBF", "\u{6FFFF}")
    assert_equal("\xF1\xA0\x80\x80", "\u{60000}")
    assert_equal("\xF1\x9F\xBF\xBF", "\u{5FFFF}")
    assert_equal("\xF1\x90\x80\x80", "\u{50000}")
    assert_equal("\xF1\x8F\xBF\xBF", "\u{4FFFF}")
    assert_equal("\xF1\x80\x80\x80", "\u{40000}")
    assert_equal("\xF0\xBF\xBF\xBF", "\u{3FFFF}")
    assert_equal("\xF0\xB0\x80\x80", "\u{30000}")
    assert_equal("\xF0\xAF\xBF\xBF", "\u{2FFFF}")
    assert_equal("\xF0\xA0\x80\x80", "\u{20000}")
    assert_equal("\xF0\x9F\xBF\xBF", "\u{1FFFF}")
    assert_equal("\xF0\x90\x80\x80", "\u{10000}")
    # BMP
    assert_equal("\xEF\xBF\xBF", "\uFFFF")
    assert_equal("\xEE\x80\x80", "\uE000")
    assert_equal("\xED\x9F\xBF", "\uD7FF")
    assert_equal("\xE0\xA0\x80", "\u0800")
    assert_equal("\xDF\xBF", "\u07FF")
    assert_equal("\xC2\x80", "\u0080")
    assert_equal("\x7F", "\u007F")
    assert_equal("\x00", "\u0000")
  end

  def test_chars
    assert_equal(?\u0041, ?A)
    assert_equal(?\u{79}, ?\x79)
    assert_equal(?\u{0}, ?\000)
    assert_equal(?\u0000, ?\000)
  end

  # Tests to make sure that disallowed cases fail
  def test_fail
     assert_raise(SyntaxError) { eval %q("\uabc") }        # too short
     assert_raise(SyntaxError) { eval %q("\uab") }         # too short
     assert_raise(SyntaxError) { eval %q("\ua") }          # too short
     assert_raise(SyntaxError) { eval %q("\u") }           # too short
     assert_raise(SyntaxError) { eval %q("\u{110000}") }   # too high
     assert_raise(SyntaxError) { eval %q("\u{abcdeff}") }  # too long
     assert_raise(SyntaxError) { eval %q("\ughij") }       # bad hex digits
     assert_raise(SyntaxError) { eval %q("\u{ghij}") }     # bad hex digits

     assert_raise(SyntaxError) { eval %q("\u{123 456 }")}  # extra space
     assert_raise(SyntaxError) { eval %q("\u{ 123 456}")}  # extra space
     assert_raise(SyntaxError) { eval %q("\u{123  456}")}  # extra space

# The utf-8 encoding object currently does not object to codepoints
# in the surrogate blocks, so these do not raise an error.
#     assert_raise(SyntaxError) { "\uD800" }       # surrogate block
#     assert_raise(SyntaxError) { "\uDCBA" }       # surrogate block
#     assert_raise(SyntaxError) { "\uDFFF" }       # surrogate block
#     assert_raise(SyntaxError) { "\uD847\uDD9A" } # surrogate pair

   end
end
