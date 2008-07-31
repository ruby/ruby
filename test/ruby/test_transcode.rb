# -*- encoding: ASCII-8BIT -*-   # make sure this runs in binary mode
# some of the comments are in UTF-8

require 'test/unit'
class TestTranscode < Test::Unit::TestCase
  def setup_really_needed? # trick to create all the necessary encodings
    all_encodings = [ 'ISO-8859-1', 'ISO-8859-2',
                      'ISO-8859-3', 'ISO-8859-4',
                      'ISO-8859-5', 'ISO-8859-6',
                      'ISO-8859-7', 'ISO-8859-8',
                      'ISO-8859-9', 'ISO-8859-10',
                      'ISO-8859-11', 'ISO-8859-13',
                      'ISO-8859-14', 'ISO-8859-15',
                      'UTF-16BE'
                    ]
    all_encodings.each do |enc|
      'abc'.encode(enc, 'UTF-8')
    end
  end

  def test_errors
    assert_raise(ArgumentError) { 'abc'.encode }
    assert_raise(ArgumentError) { 'abc'.encode! }
    assert_raise(ArgumentError) { 'abc'.encode('foo', 'bar') }
    assert_raise(ArgumentError) { 'abc'.encode!('foo', 'bar') }
    assert_raise(ArgumentError) { 'abc'.force_encoding('utf-8').encode('foo') }
    assert_raise(ArgumentError) { 'abc'.force_encoding('utf-8').encode!('foo') }
    assert_raise(RuntimeError) { "\x80".encode('utf-8','ASCII-8BIT') }
    assert_raise(RuntimeError) { "\x80".encode('utf-8','US-ASCII') }
    assert_raise(RuntimeError) { "\xA5".encode('utf-8','iso-8859-3') }
  end

  def test_arguments
    assert_equal('abc', 'abc'.force_encoding('utf-8').encode('iso-8859-1'))
    # check that encoding is kept when no conversion is done
    assert_equal('abc'.force_encoding('Shift_JIS'), 'abc'.force_encoding('Shift_JIS').encode('Shift_JIS'))
    assert_equal('abc'.force_encoding('Shift_JIS'), 'abc'.force_encoding('Shift_JIS').encode!('Shift_JIS'))
    # assert that encoding is correctly set
    assert_equal("D\u00FCrst".encoding, "D\xFCrst".force_encoding('iso-8859-1').encode('utf-8').encoding)
    # check that Encoding can be used as parameter
    assert_equal("D\u00FCrst", "D\xFCrst".encode('utf-8', Encoding.find('ISO-8859-1')))
    assert_equal("D\u00FCrst", "D\xFCrst".encode(Encoding.find('utf-8'), 'ISO-8859-1'))
    assert_equal("D\u00FCrst", "D\xFCrst".encode(Encoding.find('utf-8'), Encoding.find('ISO-8859-1')))
  end

  def test_length
    assert_equal("\u20AC"*20, ("\xA4"*20).encode('utf-8', 'iso-8859-15'))
    assert_equal("\u20AC"*20, ("\xA4"*20).encode!('utf-8', 'iso-8859-15'))
    assert_equal("\u20AC"*2000, ("\xA4"*2000).encode('utf-8', 'iso-8859-15'))
    assert_equal("\u20AC"*2000, ("\xA4"*2000).encode!('utf-8', 'iso-8859-15'))
    assert_equal("\u20AC"*200000, ("\xA4"*200000).encode('utf-8', 'iso-8859-15'))
    assert_equal("\u20AC"*200000, ("\xA4"*200000).encode!('utf-8', 'iso-8859-15'))
  end

  def check_both_ways(utf8, raw, encoding)
    assert_equal(utf8.force_encoding('utf-8'), raw.encode('utf-8', encoding))
    assert_equal(raw.force_encoding(encoding), utf8.encode(encoding, 'utf-8'))
  end

  def test_encodings
    check_both_ways("\u307E\u3064\u3082\u3068 \u3086\u304D\u3072\u308D",
        "\x82\xdc\x82\xc2\x82\xe0\x82\xc6 \x82\xe4\x82\xab\x82\xd0\x82\xeb", 'shift_jis') # まつもと ゆきひろ
    check_both_ways("\u307E\u3064\u3082\u3068 \u3086\u304D\u3072\u308D",
        "\xa4\xde\xa4\xc4\xa4\xe2\xa4\xc8 \xa4\xe6\xa4\xad\xa4\xd2\xa4\xed", 'euc-jp')
    check_both_ways("\u677E\u672C\u884C\u5F18", "\x8f\xbc\x96\x7b\x8d\x73\x8d\x4f", 'shift_jis') # 松本行弘
    check_both_ways("\u677E\u672C\u884C\u5F18", "\xbe\xbe\xcb\xdc\xb9\xd4\xb9\xb0", 'euc-jp')
    check_both_ways("D\u00FCrst", "D\xFCrst", 'iso-8859-1') # Dürst
    check_both_ways("D\u00FCrst", "D\xFCrst", 'iso-8859-2')
    check_both_ways("D\u00FCrst", "D\xFCrst", 'iso-8859-3')
    check_both_ways("D\u00FCrst", "D\xFCrst", 'iso-8859-4')
    check_both_ways("D\u00FCrst", "D\xFCrst", 'iso-8859-9')
    check_both_ways("D\u00FCrst", "D\xFCrst", 'iso-8859-10')
    check_both_ways("D\u00FCrst", "D\xFCrst", 'iso-8859-13')
    check_both_ways("D\u00FCrst", "D\xFCrst", 'iso-8859-14')
    check_both_ways("D\u00FCrst", "D\xFCrst", 'iso-8859-15')
    check_both_ways("r\u00E9sum\u00E9", "r\xE9sum\xE9", 'iso-8859-1') # résumé
    check_both_ways("\u0065\u006C\u0151\u00ED\u0072\u00E1\u0073", "el\xF5\xEDr\xE1s", 'iso-8859-2') # előírás
    check_both_ways("\u043F\u0435\u0440\u0435\u0432\u043E\u0434",
         "\xDF\xD5\xE0\xD5\xD2\xDE\xD4", 'iso-8859-5') # перевод
    check_both_ways("\u0643\u062A\u0628", "\xE3\xCA\xC8", 'iso-8859-6') # كتب
    check_both_ways("\u65E5\u8A18", "\x93\xFA\x8BL", 'shift_jis') # 日記
    check_both_ways("\u65E5\u8A18", "\xC6\xFC\xB5\xAD", 'euc-jp')
    check_both_ways("\uC560\uC778\uAD6C\uD568\u0020\u6734\uC9C0\uC778",
         "\xBE\xD6\xC0\xCE\xB1\xB8\xC7\xD4\x20\xDA\xD3\xC1\xF6\xC0\xCE", 'euc-kr') # 애인구함 朴지인
    check_both_ways("\uC544\uD58F\uD58F\u0020\uB620\uBC29\uD6BD\uB2D8\u0020\uC0AC\uB791\uD716",
         "\xBE\xC6\xC1\x64\xC1\x64\x20\x8C\x63\xB9\xE6\xC4\x4F\xB4\xD4\x20\xBB\xE7\xB6\xFB\xC5\x42", 'cp949') # 아햏햏 똠방횽님 사랑휖
  end

  def test_twostep
    assert_equal("D\xFCrst".force_encoding('iso-8859-2'), "D\xFCrst".encode('iso-8859-2', 'iso-8859-1'))
  end

  def test_ascii_range
    encodings = [
      'US-ASCII', 'ASCII-8BIT',
      'ISO-8859-1', 'ISO-8859-2', 'ISO-8859-3',
      'ISO-8859-4', 'ISO-8859-5', 'ISO-8859-6',
      'ISO-8859-7', 'ISO-8859-8', 'ISO-8859-9',
      'ISO-8859-10', 'ISO-8859-11', 'ISO-8859-13',
      'ISO-8859-14', 'ISO-8859-15',
      'EUC-JP', 'SHIFT_JIS', 'EUC-KR'
    ]
    all_ascii = (0..127).to_a.pack 'C*'
    encodings.each do |enc|
      test_start = all_ascii
      assert_equal(test_start, test_start.encode('UTF-8',enc).encode(enc).force_encoding('ASCII-8BIT')) 
    end
  end

  def test_all_bytes
    encodings_8859 = [
      'ISO-8859-1', 'ISO-8859-2',
      #'ISO-8859-3', # not all bytes used
      'ISO-8859-4', 'ISO-8859-5',
      #'ISO-8859-6', # not all bytes used
      #'ISO-8859-7', # not all bytes used
      #'ISO-8859-8', # not all bytes used
      'ISO-8859-9', 'ISO-8859-10',
      #'ISO-8859-11', # not all bytes used
      #'ISO-8859-12', # not available
      'ISO-8859-13','ISO-8859-14','ISO-8859-15',
      #'ISO-8859-16', # not available
    ]
    all_bytes = (0..255).to_a.pack 'C*'
    encodings_8859.each do |enc|
      test_start = all_bytes
      assert_equal(test_start, test_start.encode('UTF-8',enc).encode(enc).force_encoding('ASCII-8BIT')) 
    end
  end

  def check_utf_16_both_ways(utf8, raw)
    copy = raw.dup
    0.step(copy.length-1, 2) { |i| copy[i+1], copy[i] = copy[i], copy[i+1] }
    check_both_ways(utf8, raw, 'utf-16be')
    check_both_ways(utf8, copy, 'utf-16le')
  end

  def test_utf_16
    check_utf_16_both_ways("abc", "\x00a\x00b\x00c")
    check_utf_16_both_ways("\u00E9", "\x00\xE9");
    check_utf_16_both_ways("\u00E9\u0070\u00E9\u0065", "\x00\xE9\x00\x70\x00\xE9\x00\x65") # épée
    check_utf_16_both_ways("\u677E\u672C\u884C\u5F18", "\x67\x7E\x67\x2C\x88\x4C\x5F\x18") # 松本行弘
    check_utf_16_both_ways("\u9752\u5C71\u5B66\u9662\u5927\u5B66", "\x97\x52\x5C\x71\x5B\x66\x96\x62\x59\x27\x5B\x66") # 青山学院大学
    check_utf_16_both_ways("Martin D\u00FCrst", "\x00M\x00a\x00r\x00t\x00i\x00n\x00 \x00D\x00\xFC\x00r\x00s\x00t") # Martin Dürst
    # BMP
    check_utf_16_both_ways("\u0000", "\x00\x00")
    check_utf_16_both_ways("\u007F", "\x00\x7F")
    check_utf_16_both_ways("\u0080", "\x00\x80")
    check_utf_16_both_ways("\u0555", "\x05\x55")
    check_utf_16_both_ways("\u04AA", "\x04\xAA")
    check_utf_16_both_ways("\u0333", "\x03\x33")
    check_utf_16_both_ways("\u04CC", "\x04\xCC")
    check_utf_16_both_ways("\u00F0", "\x00\xF0")
    check_utf_16_both_ways("\u070F", "\x07\x0F")
    check_utf_16_both_ways("\u07FF", "\x07\xFF")
    check_utf_16_both_ways("\u0800", "\x08\x00")
    check_utf_16_both_ways("\uD7FF", "\xD7\xFF")
    check_utf_16_both_ways("\uE000", "\xE0\x00")
    check_utf_16_both_ways("\uFFFF", "\xFF\xFF")
    check_utf_16_both_ways("\u5555", "\x55\x55")
    check_utf_16_both_ways("\uAAAA", "\xAA\xAA")
    check_utf_16_both_ways("\u3333", "\x33\x33")
    check_utf_16_both_ways("\uCCCC", "\xCC\xCC")
    check_utf_16_both_ways("\uF0F0", "\xF0\xF0")
    check_utf_16_both_ways("\u0F0F", "\x0F\x0F")
    check_utf_16_both_ways("\uFF00", "\xFF\x00")
    check_utf_16_both_ways("\u00FF", "\x00\xFF")
    # outer planes
    check_utf_16_both_ways("\u{10000}", "\xD8\x00\xDC\x00")
    check_utf_16_both_ways("\u{FFFFF}", "\xDB\xBF\xDF\xFF")
    check_utf_16_both_ways("\u{100000}", "\xDB\xC0\xDC\x00")
    check_utf_16_both_ways("\u{10FFFF}", "\xDB\xFF\xDF\xFF")
    check_utf_16_both_ways("\u{105555}", "\xDB\xD5\xDD\x55")
    check_utf_16_both_ways("\u{55555}", "\xD9\x15\xDD\x55")
    check_utf_16_both_ways("\u{AAAAA}", "\xDA\x6A\xDE\xAA")
    check_utf_16_both_ways("\u{33333}", "\xD8\x8C\xDF\x33")
    check_utf_16_both_ways("\u{CCCCC}", "\xDA\xF3\xDC\xCC")
    check_utf_16_both_ways("\u{8F0F0}", "\xD9\xFC\xDC\xF0")
    check_utf_16_both_ways("\u{F0F0F}", "\xDB\x83\xDF\x0F")
    check_utf_16_both_ways("\u{8FF00}", "\xD9\xFF\xDF\x00")
    check_utf_16_both_ways("\u{F00FF}", "\xDB\x80\xDC\xFF")
  end

  def check_utf_32_both_ways(utf8, raw)
    copy = raw.dup
    0.step(copy.length-1, 4) do |i|
      copy[i+3], copy[i+2], copy[i+1], copy[i] = copy[i], copy[i+1], copy[i+2], copy[i+3]
    end
    check_both_ways(utf8, raw, 'utf-32be')
    #check_both_ways(utf8, copy, 'utf-32le')
  end

  def test_utf_32
    check_utf_32_both_ways("abc", "\x00\x00\x00a\x00\x00\x00b\x00\x00\x00c")
    check_utf_32_both_ways("\u00E9", "\x00\x00\x00\xE9");
    check_utf_32_both_ways("\u00E9\u0070\u00E9\u0065",
      "\x00\x00\x00\xE9\x00\x00\x00\x70\x00\x00\x00\xE9\x00\x00\x00\x65") # épée
    check_utf_32_both_ways("\u677E\u672C\u884C\u5F18",
      "\x00\x00\x67\x7E\x00\x00\x67\x2C\x00\x00\x88\x4C\x00\x00\x5F\x18") # 松本行弘
    check_utf_32_both_ways("\u9752\u5C71\u5B66\u9662\u5927\u5B66",
      "\x00\x00\x97\x52\x00\x00\x5C\x71\x00\x00\x5B\x66\x00\x00\x96\x62\x00\x00\x59\x27\x00\x00\x5B\x66") # 青山学院大学
    check_utf_32_both_ways("Martin D\u00FCrst",
      "\x00\x00\x00M\x00\x00\x00a\x00\x00\x00r\x00\x00\x00t\x00\x00\x00i\x00\x00\x00n\x00\x00\x00 \x00\x00\x00D\x00\x00\x00\xFC\x00\x00\x00r\x00\x00\x00s\x00\x00\x00t") # Martin Dürst
    # BMP
    check_utf_32_both_ways("\u0000", "\x00\x00\x00\x00")
    check_utf_32_both_ways("\u007F", "\x00\x00\x00\x7F")
    check_utf_32_both_ways("\u0080", "\x00\x00\x00\x80")
    check_utf_32_both_ways("\u0555", "\x00\x00\x05\x55")
    check_utf_32_both_ways("\u04AA", "\x00\x00\x04\xAA")
    check_utf_32_both_ways("\u0333", "\x00\x00\x03\x33")
    check_utf_32_both_ways("\u04CC", "\x00\x00\x04\xCC")
    check_utf_32_both_ways("\u00F0", "\x00\x00\x00\xF0")
    check_utf_32_both_ways("\u070F", "\x00\x00\x07\x0F")
    check_utf_32_both_ways("\u07FF", "\x00\x00\x07\xFF")
    check_utf_32_both_ways("\u0800", "\x00\x00\x08\x00")
    check_utf_32_both_ways("\uD7FF", "\x00\x00\xD7\xFF")
    check_utf_32_both_ways("\uE000", "\x00\x00\xE0\x00")
    check_utf_32_both_ways("\uFFFF", "\x00\x00\xFF\xFF")
    check_utf_32_both_ways("\u5555", "\x00\x00\x55\x55")
    check_utf_32_both_ways("\uAAAA", "\x00\x00\xAA\xAA")
    check_utf_32_both_ways("\u3333", "\x00\x00\x33\x33")
    check_utf_32_both_ways("\uCCCC", "\x00\x00\xCC\xCC")
    check_utf_32_both_ways("\uF0F0", "\x00\x00\xF0\xF0")
    check_utf_32_both_ways("\u0F0F", "\x00\x00\x0F\x0F")
    check_utf_32_both_ways("\uFF00", "\x00\x00\xFF\x00")
    check_utf_32_both_ways("\u00FF", "\x00\x00\x00\xFF")
    # outer planes
    check_utf_32_both_ways("\u{10000}", "\x00\x01\x00\x00")
    check_utf_32_both_ways("\u{FFFFF}", "\x00\x0F\xFF\xFF")
    check_utf_32_both_ways("\u{100000}","\x00\x10\x00\x00")
    check_utf_32_both_ways("\u{10FFFF}","\x00\x10\xFF\xFF")
    check_utf_32_both_ways("\u{105555}","\x00\x10\x55\x55")
    check_utf_32_both_ways("\u{55555}", "\x00\x05\x55\x55")
    check_utf_32_both_ways("\u{AAAAA}", "\x00\x0A\xAA\xAA")
    check_utf_32_both_ways("\u{33333}", "\x00\x03\x33\x33")
    check_utf_32_both_ways("\u{CCCCC}", "\x00\x0C\xCC\xCC")
    check_utf_32_both_ways("\u{8F0F0}", "\x00\x08\xF0\xF0")
    check_utf_32_both_ways("\u{F0F0F}", "\x00\x0F\x0F\x0F")
    check_utf_32_both_ways("\u{8FF00}", "\x00\x08\xFF\x00")
    check_utf_32_both_ways("\u{F00FF}", "\x00\x0F\x00\xFF")
  end
  
  def test_invalid_ignore
    # arguments only
    assert_nothing_raised { 'abc'.encode('utf-8', invalid: :ignore) }
    # check handling of UTF-8 ill-formed subsequences
    assert_equal("\x00\x41\x00\x3E\x00\x42".force_encoding('UTF-16BE'),
      "\x41\xC2\x3E\x42".encode('UTF-16BE', 'UTF-8', invalid: :ignore))
    assert_equal("\x00\x41\x00\xF1\x00\x42".force_encoding('UTF-16BE'),
      "\x41\xC2\xC3\xB1\x42".encode('UTF-16BE', 'UTF-8', invalid: :ignore))
    assert_equal("\x00\x42".force_encoding('UTF-16BE'),
      "\xF0\x80\x80\x42".encode('UTF-16BE', 'UTF-8', invalid: :ignore))
    assert_equal(''.force_encoding('UTF-16BE'),
      "\x82\xAB".encode('UTF-16BE', 'UTF-8', invalid: :ignore))
  end

  def test_shift_jis
    check_both_ways("\u3000", "\x81\x40", 'shift_jis') # full-width space
    check_both_ways("\u00D7", "\x81\x7E", 'shift_jis') # ~
    check_both_ways("\u00F7", "\x81\x80", 'shift_jis') # 
    check_both_ways("\u25C7", "\x81\x9E", 'shift_jis') # 
    check_both_ways("\u25C6", "\x81\x9F", 'shift_jis') # 
    check_both_ways("\u25EF", "\x81\xFC", 'shift_jis') # 
    check_both_ways("\u6A97", "\x9F\x40", 'shift_jis') # @
    check_both_ways("\u6BEF", "\x9F\x7E", 'shift_jis') # ~
    check_both_ways("\u9EBE", "\x9F\x80", 'shift_jis') # 
    check_both_ways("\u6CBE", "\x9F\x9E", 'shift_jis') # 
    check_both_ways("\u6CBA", "\x9F\x9F", 'shift_jis') # 
    check_both_ways("\u6ECC", "\x9F\xFC", 'shift_jis') # 
    check_both_ways("\u6F3E", "\xE0\x40", 'shift_jis') # @
    check_both_ways("\u70DD", "\xE0\x7E", 'shift_jis') # ~
    check_both_ways("\u70D9", "\xE0\x80", 'shift_jis') # 
    check_both_ways("\u71FC", "\xE0\x9E", 'shift_jis') # 
    check_both_ways("\u71F9", "\xE0\x9F", 'shift_jis') # 
    check_both_ways("\u73F1", "\xE0\xFC", 'shift_jis') # 
    assert_raise(RuntimeError) { "\xEF\x40".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xEF\x7E".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xEF\x80".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xEF\x9E".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xEF\x9F".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xEF\xFC".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xF0\x40".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xF0\x7E".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xF0\x80".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xF0\x9E".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xF0\x9F".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xF0\xFC".encode("utf-8", 'shift_jis') }
    check_both_ways("\u9ADC", "\xFC\x40", 'shift_jis') # @
    assert_raise(RuntimeError) { "\xFC\x7E".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xFC\x80".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xFC\x9E".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xFC\x9F".encode("utf-8", 'shift_jis') }
    assert_raise(RuntimeError) { "\xFC\xFC".encode("utf-8", 'shift_jis') }
    check_both_ways("\u677E\u672C\u884C\u5F18", "\x8f\xbc\x96\x7b\x8d\x73\x8d\x4f", 'shift_jis') # {sO
    check_both_ways("\u9752\u5C71\u5B66\u9662\u5927\u5B66", "\x90\xC2\x8E\x52\x8A\x77\x89\x40\x91\xE5\x8A\x77", 'shift_jis') # Rw@w
    check_both_ways("\u795E\u6797\u7FA9\u535A", "\x90\x5F\x97\xD1\x8B\x60\x94\x8E", 'shift_jis') # _ы`
  end

  def test_iso_2022_jp
    assert_raise(RuntimeError) { "\x1b(A".encode("utf-8", "iso-2022-jp") }
    assert_raise(RuntimeError) { "\x1b$(A".encode("utf-8", "iso-2022-jp") }
    assert_raise(RuntimeError) { "\x1b$C".encode("utf-8", "iso-2022-jp") }
    assert_raise(RuntimeError) { "\x1e".encode("utf-8", "iso-2022-jp") }
    assert_raise(RuntimeError) { "\x80".encode("utf-8", "iso-2022-jp") }
    assert_raise(RuntimeError) { "\x1b$(Dd!\x1b(B".encode("utf-8", "iso-2022-jp") }
    assert_raise(RuntimeError) { "\u9299".encode("iso-2022-jp") }
    #@@@@ TODO: the next test should actually fail, because iso-2022-jp does not include half-width kana
    check_both_ways("\uff71\uff72\uff73\uff74\uff75", "\x1b(I12345\x1b(B", "iso-2022-jp") # JIS X 0201 ｧｨｩｪｫ
  end
  
  def test_iso_2022_jp_1
    # check_both_ways("\u9299", "\x1b$(Dd!\x1b(B", "iso-2022-jp-1") # JIS X 0212 区68 点01 銙
  end
  
  def test_unicode_public_review_issue_121 # see http://www.unicode.org/review/pr-121.html
    # assert_equal("\x00\x61\xFF\xFD\x00\x62".force_encoding('UTF-16BE'),
    #   "\x61\xF1\x80\x80\xE1\x80\xC2\x62".encode('UTF-16BE', 'UTF-8', invalid: :replace)) # option 1
    assert_equal("\x00\x61\xFF\xFD\xFF\xFD\xFF\xFD\x00\x62".force_encoding('UTF-16BE'),
      "\x61\xF1\x80\x80\xE1\x80\xC2\x62".encode('UTF-16BE', 'UTF-8', invalid: :replace)) # option 2
    assert_equal("\x61\x00\xFD\xFF\xFD\xFF\xFD\xFF\x62\x00".force_encoding('UTF-16LE'),
      "\x61\xF1\x80\x80\xE1\x80\xC2\x62".encode('UTF-16LE', 'UTF-8', invalid: :replace)) # option 2
    # assert_equal("\x00\x61\xFF\xFD\xFF\xFD\xFF\xFD\xFF\xFD\xFF\xFD\xFF\xFD\x00\x62".force_encoding('UTF-16BE'),
    # "\x61\xF1\x80\x80\xE1\x80\xC2\x62".encode('UTF-16BE', 'UTF-8', invalid: :replace)) # option 3
  end
end
