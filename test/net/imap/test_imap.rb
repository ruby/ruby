require "net/imap"
require "test/unit"

class IMAPTest < Test::Unit::TestCase
  def test_encode_utf7
    s = Net::IMAP.encode_utf7("\357\274\241\357\274\242\357\274\243")
    assert_equal("&,yH,Iv8j-", s)
  end

  def test_decode_utf7
    s = Net::IMAP.decode_utf7("&,yH,Iv8j-")
    assert_equal("\357\274\241\357\274\242\357\274\243", s)
  end
end
