require "net/imap"
require "test/unit"

class IMAPTest < Test::Unit::TestCase
  def test_encode_utf7
    utf8 = "\357\274\241\357\274\242\357\274\243".force_encoding("UTF-8")
    s = Net::IMAP.encode_utf7(utf8)
    assert_equal("&,yH,Iv8j-".force_encoding("UTF-8"), s)
  end

  def test_decode_utf7
    s = Net::IMAP.decode_utf7("&,yH,Iv8j-")
    utf8 = "\357\274\241\357\274\242\357\274\243".force_encoding("UTF-8")
    assert_equal(utf8, s)
  end
end
