require 'net/http'
require 'test/unit'

module TestHTTP
  class HTTPConnectionTest < Test::Unit::TestCase
    def test_connection_refused_in_request
      bug2708 = '[ruby-core:28028]'
      port = nil
      localhost = "127.0.0.1"
      t = Thread.new {
        TCPServer.open(localhost, 0) do |serv|
          _, port, _, _ = serv.addr
          if clt = serv.accept
            clt.close
          end
        end
      }
      begin
        sleep 0.1 until port
        assert_raise(EOFError, bug2708) {
          n = Net::HTTP.new(localhost, port)
          n.request_get('/')
        }
      ensure
        t.join if t
      end
      assert_raise(Errno::ECONNREFUSED, bug2708) {
        n = Net::HTTP.new(localhost, port)
        n.request_get('/')
      }
    end
  end
end
