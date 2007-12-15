# -*- encoding: ASCII-8BIT -*-   # make sure this runs in binary mode

require 'test/unit'
class TestTranscode < Test::Unit::TestCase
  def setup # trick to create all the necessary encodings
    all_encodings = [ 'ISO-8859-1', 'ISO-8859-2',
                      'ISO-8859-3', 'ISO-8859-4',
                      'ISO-8859-5', 'ISO-8859-6',
                      'ISO-8859-7', 'ISO-8859-8',
                      'ISO-8859-9', 'ISO-8859-10',
                      'ISO-8859-11', 'ISO-8859-13',
                      'ISO-8859-14', 'ISO-8859-15'
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
    assert_raise(ArgumentError) { 'abc'.force_encoding('Shift_JIS').encode('UTF-8') } # temporary
    assert_raise(ArgumentError) { 'abc'.force_encoding('Shift_JIS').encode!('UTF-8') } # temporary
    assert_raise(ArgumentError) { 'abc'.encode('foo', 'bar') }
    assert_raise(ArgumentError) { 'abc'.encode!('foo', 'bar') }
    assert_raise(ArgumentError) { 'abc'.force_encoding('utf-8').encode('foo') }
    assert_raise(ArgumentError) { 'abc'.force_encoding('utf-8').encode!('foo') }
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
  
  def test_encodings
    # temporary, fix encoding
    assert_equal("D\u00FCrst", "D\xFCrst".force_encoding('iso-8859-1').encode('utf-8'))
    assert_equal("D\u00FCrst", "D\xFCrst".encode('utf-8', 'iso-8859-1'))
    assert_equal("D\u00FCrst", "D\xFCrst".encode('utf-8', 'iso-8859-2'))
    assert_equal("D\u00FCrst", "D\xFCrst".encode('utf-8', 'iso-8859-3'))
    assert_equal("D\u00FCrst", "D\xFCrst".encode('utf-8', 'iso-8859-4'))
    assert_equal("D\u00FCrst", "D\xFCrst".encode('utf-8', 'iso-8859-9'))
    assert_equal("D\u00FCrst", "D\xFCrst".encode('utf-8', 'iso-8859-10'))
    assert_equal("D\u00FCrst", "D\xFCrst".encode('utf-8', 'iso-8859-13'))
    assert_equal("D\u00FCrst", "D\xFCrst".encode('utf-8', 'iso-8859-14'))
    assert_equal("D\u00FCrst", "D\xFCrst".encode('utf-8', 'iso-8859-15'))
    assert_equal("D\xFCrst".force_encoding('iso-8859-1'), "D\u00FCrst".encode('iso-8859-1'))
    assert_equal("D\xFCrst".force_encoding('iso-8859-2'), "D\u00FCrst".encode('iso-8859-2'))
    assert_equal("D\xFCrst".force_encoding('iso-8859-3').encoding, "D\u00FCrst".encode('iso-8859-3').encoding)
    assert_equal("D\xFCrst".force_encoding('iso-8859-4'), "D\u00FCrst".encode('iso-8859-4'))
    assert_equal("D\xFCrst".force_encoding('iso-8859-9'), "D\u00FCrst".encode('iso-8859-9'))
    assert_equal("D\xFCrst".force_encoding('iso-8859-10'), "D\u00FCrst".encode('iso-8859-10'))
    assert_equal("D\xFCrst".force_encoding('iso-8859-13'), "D\u00FCrst".encode('iso-8859-13'))
    assert_equal("D\xFCrst".force_encoding('iso-8859-14'), "D\u00FCrst".encode('iso-8859-14'))
    assert_equal("D\xFCrst".force_encoding('iso-8859-15'), "D\u00FCrst".encode('iso-8859-15'))
    assert_equal("r\xE9sum\xE9".force_encoding('iso-8859-1'), "r\u00E9sum\u00E9".encode('iso-8859-1'))
    assert_equal("el\xF5\xEDr\xE1s".force_encoding('iso-8859-2'),
        "\u0065\u006C\u0151\u00ED\u0072\u00E1\u0073".encode('iso-8859-2'))
    assert_equal("\xE3\xCA\xC8".force_encoding('iso-8859-6'), "\u0643\u062A\u0628".encode('iso-8859-6'))
    assert_equal( "\xDF\xD5\xE0\xD5\xD2\xDE\xD4".force_encoding('iso-8859-5'),
        "\u043F\u0435\u0440\u0435\u0432\u043E\u0434".encode('iso-8859-5'))
  end

  def test_twostep
    assert_equal("D\xFCrst".force_encoding('iso-8859-2'), "D\xFCrst".encode('iso-8859-2', 'iso-8859-1'))
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
    all_bytes = (0..255).collect {|x| x}.pack 'C*'
    test_start = all_bytes
    test_start.encode('UTF-8','ISO-8859-1').encode('ISO-8859-1')
    encodings_8859.each do |enc|
      test_start = all_bytes
      assert_equal(test_start, test_start.encode('UTF-8',enc).encode(enc).force_encoding('ASCII-8BIT')) 
    end
  end
end
