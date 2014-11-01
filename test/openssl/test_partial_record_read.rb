require_relative "utils"

if defined?(OpenSSL)

  class OpenSSL::TestPartialRecordRead < OpenSSL::SSLTestCase
    def test_partial_tls_record_read_nonblock
      port = 12345

      start_server(port, OpenSSL::SSL::VERIFY_NONE, true, :server_proc =>
          Proc.new do |server_ctx, server_ssl|
            begin
              server_ssl.io.write("\x01") # the beginning of a TLS record
              sleep 6                     # do not finish prematurely before the read by the client is attempted
            ensure
              server_ssl.close
            end
          end,
          :ignore_listener_error => false
      ) do |server, port|
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.sync_close = true
        begin
          ssl.connect
          sleep 3  # wait is required for the (incomplete) TLS record to arrive at the client socket

          # Should raise a IO::WaitReadable since a full TLS record is not available for reading.
          assert_raise(IO::WaitReadable) { ssl.read_nonblock(1) }
        ensure
          ssl.close
        end
      end
    end

  end

end
