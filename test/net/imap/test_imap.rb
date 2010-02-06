require "net/imap"
require "test/unit"

class IMAPTest < Test::Unit::TestCase
  def setup
    @do_not_reverse_lookup = Socket.do_not_reverse_lookup
    Socket.do_not_reverse_lookup = true
  end

  def teardown
    Socket.do_not_reverse_lookup = @do_not_reverse_lookup
  end

  def test_parse_nomodesq
    parser = Net::IMAP::ResponseParser.new
    r = parser.parse(%Q'* OK [NOMODSEQ] Sorry, modsequences have not been enabled on this mailbox\r\n')
    assert_equal("OK", r.name)
    assert_equal("NOMODSEQ", r.data.code.name)
  end

  def test_unexpected_bye
    server = TCPServer.new(0)
    port = server.addr[1]
    Thread.start do
      begin
        sock = server.accept
        begin
          sock.print("* OK Gimap ready for requests from 75.101.246.151 33if2752585qyk.26\r\n")
          sock.gets
          sock.print("* BYE System Error 33if2752585qyk.26\r\n")
        ensure
          sock.close
        end
      rescue
      end
    end
    begin
      begin
        imap = Net::IMAP.new("localhost", port)
        assert_raise(Net::IMAP::ByeResponseError) do
          imap.login("user", "password")
        end
      end
    ensure
      server.close
    end
  end
end
