require 'test/unit'
require 'net/http'
require 'stringio'

class HTTPPostIOTest < Test::Unit::TestCase
  def test_post_io_chunk_size
    t = nil
    TCPServer.open("127.0.0.1", 0) {|serv|
      _, port, _, _ = serv.addr
      t = Thread.new {
        begin
          req = Net::HTTP::Post.new("/test.cgi")
          req['Transfer-Encoding'] = 'chunked'
          req.body_stream = StringIO.new("\0" * (16 * 1024 + 1))
          http = Net::HTTP.new("127.0.0.1", port)
          res = http.start { |http| http.request(req) }
        rescue EOFError
        end
      }
      sock = serv.accept
      begin
        assert_match(/chunked/, sock.gets("\r\n\r\n"))
        chunk_header = sock.gets.chomp
        assert_equal(16 * 1024, chunk_header.to_i(16))
        sock.read(chunk_header.to_i(16))
        # parse chunked stream to the end
        assert_equal("\r\n", sock.read(2))
        assert_equal("1\r\n", sock.read(3))
        assert_equal("\0\r\n", sock.read(3))
        assert_equal("0\r\n\r\n", sock.read(5))
      ensure
        sock.close
      end
    }
  ensure
    t.join if t
  end
end
