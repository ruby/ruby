require "net/imap"
require "test/unit"

class IMAPTest < Test::Unit::TestCase
  def test_parse_nomodesq
    parser = Net::IMAP::ResponseParser.new
    r = parser.parse(%Q'* OK [NOMODSEQ] Sorry, modsequences have not been enabled on this mailbox\r\n')
    assert_equal("OK", r.name)
    assert_equal("NOMODSEQ", r.data.code.name)
  end
end
