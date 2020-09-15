require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP.get" do
  before :each do
    NetHTTPSpecs.start_server
    @port = NetHTTPSpecs.port
  end

  after :each do
    NetHTTPSpecs.stop_server
  end

  describe "when passed URI" do
    it "returns the body of the specified uri" do
      Net::HTTP.get(URI.parse("http://localhost:#{@port}/")).should == "This is the index page."
    end
  end

  describe "when passed host, path, port" do
    it "returns the body of the specified host-path-combination" do
      Net::HTTP.get('localhost', "/", @port).should == "This is the index page."
    end
  end
end

quarantine! do # These specs fail frequently with CHECK_LEAKS=true
describe "Net::HTTP.get" do
  describe "when reading gzipped contents" do
    def start_threads
      require 'zlib'

      server = nil
      server_thread = Thread.new do
        server = TCPServer.new("127.0.0.1", 0)
        begin
          c = server.accept
        ensure
          server.close
        end
        c.print "HTTP/1.1 200\r\n"
        c.print "Content-Type: text/plain\r\n"
        c.print "Content-Encoding: gzip\r\n"
        s = StringIO.new
        z = Zlib::GzipWriter.new(s)
        begin
          z.write 'Hello World!'
        ensure
          z.close
        end
        c.print "Content-Length: #{s.length}\r\n\r\n"
        # Write partial gzip content
        c.write s.string.byteslice(0..-2)
        c.flush
        c
      end
      Thread.pass until server && server_thread.stop?

      client_thread = Thread.new do
        Thread.current.report_on_exception = false
        Net::HTTP.get("127.0.0.1", '/', server.connect_address.ip_port)
      end

      socket = server_thread.value
      Thread.pass until client_thread.stop?

      [socket, client_thread]
    end

    it "propagates exceptions interrupting the thread and does not replace it with Zlib::BufError" do
      my_exception = Class.new(RuntimeError)
      socket, client_thread = start_threads
      begin
        client_thread.raise my_exception, "my exception"
        -> { client_thread.value }.should raise_error(my_exception)
      ensure
        socket.close
      end
    end

    ruby_version_is "3.0" do # https://bugs.ruby-lang.org/issues/13882#note-6
      it "lets the kill Thread exception goes through and does not replace it with Zlib::BufError" do
        socket, client_thread = start_threads
        begin
          client_thread.kill
          client_thread.value.should == nil
        ensure
          socket.close
        end
      end
    end
  end
end
end
