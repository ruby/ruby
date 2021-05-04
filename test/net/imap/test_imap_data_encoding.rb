# frozen_string_literal: true

require "net/imap"
require "test/unit"

class IMAPDataEncodingTest < Test::Unit::TestCase

  def test_encode_utf7
    assert_equal("foo", Net::IMAP.encode_utf7("foo"))
    assert_equal("&-", Net::IMAP.encode_utf7("&"))

    utf8 = "\357\274\241\357\274\242\357\274\243".dup.force_encoding("UTF-8")
    s = Net::IMAP.encode_utf7(utf8)
    assert_equal("&,yH,Iv8j-", s)
    s = Net::IMAP.encode_utf7("foo&#{utf8}-bar".encode("EUC-JP"))
    assert_equal("foo&-&,yH,Iv8j--bar", s)

    utf8 = "\343\201\202&".dup.force_encoding("UTF-8")
    s = Net::IMAP.encode_utf7(utf8)
    assert_equal("&MEI-&-", s)
    s = Net::IMAP.encode_utf7(utf8.encode("EUC-JP"))
    assert_equal("&MEI-&-", s)
  end

  def test_decode_utf7
    assert_equal("&", Net::IMAP.decode_utf7("&-"))
    assert_equal("&-", Net::IMAP.decode_utf7("&--"))

    s = Net::IMAP.decode_utf7("&,yH,Iv8j-")
    utf8 = "\357\274\241\357\274\242\357\274\243".dup.force_encoding("UTF-8")
    assert_equal(utf8, s)
  end

  def test_format_date
    time = Time.mktime(2009, 7, 24)
    s = Net::IMAP.format_date(time)
    assert_equal("24-Jul-2009", s)
  end

  def test_format_datetime
    time = Time.mktime(2009, 7, 24, 1, 23, 45)
    s = Net::IMAP.format_datetime(time)
    assert_match(/\A24-Jul-2009 01:23 [+\-]\d{4}\z/, s)
  end

end
