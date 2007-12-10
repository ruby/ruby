# -*- encoding: US-ASCII -*-   # make sure this runs in binary mode

class String
  # different name, because we should be able to remove this later
  def fix_encoding (encoding)
    force_encoding(encoding)
  end
end

require 'test/unit'
class TestConvert < Test::Unit::TestCase
  def test_can_call
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
    assert_equal('abc'.force_encoding('utf-8').encode('iso-8859-1'), 'abc') # temporary, fix encoding
    assert_equal("D\xFCrst".force_encoding('iso-8859-1').encode('utf-8').fix_encoding('utf-8'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-1').fix_encoding('utf-8'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-2').fix_encoding('utf-8'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-3').fix_encoding('utf-8'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-4').fix_encoding('utf-8'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-9').fix_encoding('utf-8'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-10').fix_encoding('utf-8'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-13').fix_encoding('utf-8'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-14').fix_encoding('utf-8'), "D\u00FCrst")
    assert_equal("D\xFCrst".encode('utf-8', 'iso-8859-15').fix_encoding('utf-8'), "D\u00FCrst")
    assert_equal("D\u00FCrst".encode('iso-8859-1'), "D\xFCrst")
    assert_equal("D\u00FCrst".encode('iso-8859-2'), "D\xFCrst")
    assert_equal("D\u00FCrst".encode('iso-8859-3'), "D\xFCrst")
    assert_equal("D\u00FCrst".encode('iso-8859-4'), "D\xFCrst")
    assert_equal("D\u00FCrst".encode('iso-8859-9'), "D\xFCrst")
    assert_equal("D\u00FCrst".encode('iso-8859-10'), "D\xFCrst")
    assert_equal("D\u00FCrst".encode('iso-8859-13'), "D\xFCrst")
    assert_equal("D\u00FCrst".encode('iso-8859-14'), "D\xFCrst")
    assert_equal("D\u00FCrst".encode('iso-8859-15'), "D\xFCrst")
  end
end