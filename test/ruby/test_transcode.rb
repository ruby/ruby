# -*- encoding: US-ASCII -*-   # make sure this runs in binary mode

require 'test/unit'
class TestConvert < Test::Unit::TestCase
  def test_basic
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
    assert_equal('abc'.force_encoding('utf-8').encode('iso-8859-1'), 'abc')
    # check that encoding is kept when no conversion is done
    assert_equal('abc'.force_encoding('Shift_JIS').encode('Shift_JIS'), 'abc'.force_encoding('Shift_JIS'))
    assert_equal('abc'.force_encoding('Shift_JIS').encode!('Shift_JIS'), 'abc'.force_encoding('Shift_JIS'))
    # assert that encoding is correctly set
    assert_equal("D\xFCrst".force_encoding('iso-8859-1').encode('utf-8').encoding, "D\u00FCrst".encoding)
    # check that Encoding can be used as parameter
    assert_equal("D\xFCrst".encode('utf-8', Encoding.find('ISO-8859-1')), "D\u00FCrst")
    assert_equal("D\xFCrst".encode(Encoding.find('utf-8'), 'ISO-8859-1'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode(Encoding.find('utf-8'), Encoding.find('ISO-8859-1')), "D\u00FCrst")

    # temporary, fix encoding
    assert_equal("D\xFCrst".force_encoding('iso-8859-1').encode('utf-8'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-1'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-2'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-3'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-4'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-9'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-10'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-13'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-14'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-15'), "D\u00FCrst")
    assert_equal("D\u00FCrst".encode('iso-8859-1'), "D\xFCrst".force_encoding('iso-8859-1'))
    assert_equal("D\u00FCrst".encode('iso-8859-2'), "D\xFCrst".force_encoding('iso-8859-2'))
    assert_equal("D\u00FCrst".encode('iso-8859-3'), "D\xFCrst".force_encoding('iso-8859-3'))
    assert_equal("D\u00FCrst".encode('iso-8859-4'), "D\xFCrst".force_encoding('iso-8859-4'))
    assert_equal("D\u00FCrst".encode('iso-8859-9'), "D\xFCrst".force_encoding('iso-8859-9'))
    assert_equal("D\u00FCrst".encode('iso-8859-10'), "D\xFCrst".force_encoding('iso-8859-10'))
    assert_equal("D\u00FCrst".encode('iso-8859-13'), "D\xFCrst".force_encoding('iso-8859-13'))
    assert_equal("D\u00FCrst".encode('iso-8859-14'), "D\xFCrst".force_encoding('iso-8859-14'))
    assert_equal("D\u00FCrst".encode('iso-8859-15'), "D\xFCrst".force_encoding('iso-8859-15'))
    # test length extension
    assert_equal(("\xA4"*20).encode('utf-8', 'iso-8859-15'), "\u20AC"*20)
    assert_equal(("\xA4"*20).encode!('utf-8', 'iso-8859-15'), "\u20AC"*20)
    
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
      assert_equal(test_start.encode('UTF-8',enc).encode(enc).force_encoding('ASCII-8BIT'), test_start) 
    end
  end
end
