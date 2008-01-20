# -*- encoding: ASCII-8BIT -*-   # make sure this runs in binary mode
# some of the comments are in UTF-8

require 'test/unit'
class TestTranscode < Test::Unit::TestCase
  def setup # trick to create all the necessary encodings
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
    # we don't have semantics for conversion without attribute yet
    # maybe 'convert to UTF-8' would be nice :-)
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
      'EUC-JP', 'SHIFT_JIS'
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
  
  def test_utf_16be
    check_both_ways("abc".force_encoding('UTF-8'), "\x00a\x00b\x00c", 'utf-16be')
    check_both_ways("\u00E9", "\x00\xE9", 'utf-16be');
    check_both_ways("\u00E9\u0070\u00E9\u0065", "\x00\xE9\x00\x70\x00\xE9\x00\x65", 'utf-16be') # épée
    check_both_ways("\u677E\u672C\u884C\u5F18", "\x67\x7E\x67\x2C\x88\x4C\x5F\x18", 'utf-16be') # 松本行弘
    check_both_ways("\u9752\u5C71\u5B66\u9662\u5927\u5B66", "\x97\x52\x5C\x71\x5B\x66\x96\x62\x59\x27\x5B\x66",
                    'utf-16be') # 青山学院大学
    check_both_ways("Martin D\u00FCrst", "\x00M\x00a\x00r\x00t\x00i\x00n\x00 \x00D\x00\xFC\x00r\x00s\x00t",
                    'utf-16be') # Martin Dürst
    # BMP
    check_both_ways("\u0000", "\x00\x00", 'utf-16be')
    check_both_ways("\u007F", "\x00\x7F", 'utf-16be')
    check_both_ways("\u0080", "\x00\x80", 'utf-16be')
    check_both_ways("\u0555", "\x05\x55", 'utf-16be')
    check_both_ways("\u04AA", "\x04\xAA", 'utf-16be')
    check_both_ways("\u0333", "\x03\x33", 'utf-16be')
    check_both_ways("\u04CC", "\x04\xCC", 'utf-16be')
    check_both_ways("\u00F0", "\x00\xF0", 'utf-16be')
    check_both_ways("\u070F", "\x07\x0F", 'utf-16be')
    check_both_ways("\u07FF", "\x07\xFF", 'utf-16be')
    check_both_ways("\u0800", "\x08\x00", 'utf-16be')
    check_both_ways("\uD7FF", "\xD7\xFF", 'utf-16be')
    check_both_ways("\uE000", "\xE0\x00", 'utf-16be')
    check_both_ways("\uFFFF", "\xFF\xFF", 'utf-16be')
    check_both_ways("\u5555", "\x55\x55", 'utf-16be')
    check_both_ways("\uAAAA", "\xAA\xAA", 'utf-16be')
    check_both_ways("\u3333", "\x33\x33", 'utf-16be')
    check_both_ways("\uCCCC", "\xCC\xCC", 'utf-16be')
    check_both_ways("\uF0F0", "\xF0\xF0", 'utf-16be')
    check_both_ways("\u0F0F", "\x0F\x0F", 'utf-16be')
    check_both_ways("\uFF00", "\xFF\x00", 'utf-16be')
    check_both_ways("\u00FF", "\x00\xFF", 'utf-16be')
    # outer planes
    check_both_ways("\u{10000}", "\xD8\x00\xDC\x00", 'utf-16be')
    check_both_ways("\u{FFFFF}", "\xDB\xBF\xDF\xFF", 'utf-16be')
    check_both_ways("\u{100000}", "\xDB\xC0\xDC\x00", 'utf-16be')
    check_both_ways("\u{10FFFF}", "\xDB\xFF\xDF\xFF", 'utf-16be')
    check_both_ways("\u{105555}", "\xDB\xD5\xDD\x55", 'utf-16be')
    check_both_ways("\u{55555}", "\xD9\x15\xDD\x55", 'utf-16be')
    check_both_ways("\u{AAAAA}", "\xDA\x6A\xDE\xAA", 'utf-16be')
    check_both_ways("\u{33333}", "\xD8\x8C\xDF\x33", 'utf-16be')
    check_both_ways("\u{CCCCC}", "\xDA\xF3\xDC\xCC", 'utf-16be')
    check_both_ways("\u{8F0F0}", "\xD9\xFC\xDC\xF0", 'utf-16be')
    check_both_ways("\u{F0F0F}", "\xDB\x83\xDF\x0F", 'utf-16be')
    check_both_ways("\u{8FF00}", "\xD9\xFF\xDF\x00", 'utf-16be')
    check_both_ways("\u{F00FF}", "\xDB\x80\xDC\xFF", 'utf-16be')
  end
end
