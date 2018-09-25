require_relative '../spec_helper'
require_relative '../fixtures/classes'

platform_is_not :windows do # hangs
  describe "Socket::BasicSocket#shutdown" do
    SocketSpecs.each_ip_protocol do |family, ip_address|
      before do
        @server = Socket.new(family, :STREAM)
        @client = Socket.new(family, :STREAM)

        @server.bind(Socket.sockaddr_in(0, ip_address))
        @server.listen(1)

        @client.connect(@server.getsockname)
      end

      after do
        @client.close
        @server.close
      end

      describe 'using an Integer' do
        it 'shuts down a socket for reading' do
          @client.shutdown(Socket::SHUT_RD)

          @client.recv(1).should be_empty
        end

        it 'shuts down a socket for writing' do
          @client.shutdown(Socket::SHUT_WR)

          lambda { @client.write('hello') }.should raise_error(Errno::EPIPE)
        end

        it 'shuts down a socket for reading and writing' do
          @client.shutdown(Socket::SHUT_RDWR)

          @client.recv(1).should be_empty

          lambda { @client.write('hello') }.should raise_error(Errno::EPIPE)
        end

        it 'raises ArgumentError when using an invalid option' do
          lambda { @server.shutdown(666) }.should raise_error(ArgumentError)
        end
      end

      describe 'using a Symbol' do
        it 'shuts down a socket for reading using :RD' do
          @client.shutdown(:RD)

          @client.recv(1).should be_empty
        end

        it 'shuts down a socket for reading using :SHUT_RD' do
          @client.shutdown(:SHUT_RD)

          @client.recv(1).should be_empty
        end

        it 'shuts down a socket for writing using :WR' do
          @client.shutdown(:WR)

          lambda { @client.write('hello') }.should raise_error(Errno::EPIPE)
        end

        it 'shuts down a socket for writing using :SHUT_WR' do
          @client.shutdown(:SHUT_WR)

          lambda { @client.write('hello') }.should raise_error(Errno::EPIPE)
        end

        it 'shuts down a socket for reading and writing' do
          @client.shutdown(:RDWR)

          @client.recv(1).should be_empty

          lambda { @client.write('hello') }.should raise_error(Errno::EPIPE)
        end

        it 'raises ArgumentError when using an invalid option' do
          lambda { @server.shutdown(:Nope) }.should raise_error(SocketError)
        end
      end

      describe 'using a String' do
        it 'shuts down a socket for reading using "RD"' do
          @client.shutdown('RD')

          @client.recv(1).should be_empty
        end

        it 'shuts down a socket for reading using "SHUT_RD"' do
          @client.shutdown('SHUT_RD')

          @client.recv(1).should be_empty
        end

        it 'shuts down a socket for writing using "WR"' do
          @client.shutdown('WR')

          lambda { @client.write('hello') }.should raise_error(Errno::EPIPE)
        end

        it 'shuts down a socket for writing using "SHUT_WR"' do
          @client.shutdown('SHUT_WR')

          lambda { @client.write('hello') }.should raise_error(Errno::EPIPE)
        end

        it 'raises ArgumentError when using an invalid option' do
          lambda { @server.shutdown('Nope') }.should raise_error(SocketError)
        end
      end

      describe 'using an object that responds to #to_str' do
        before do
          @dummy = mock(:dummy)
        end

        it 'shuts down a socket for reading using "RD"' do
          @dummy.stub!(:to_str).and_return('RD')

          @client.shutdown(@dummy)

          @client.recv(1).should be_empty
        end

        it 'shuts down a socket for reading using "SHUT_RD"' do
          @dummy.stub!(:to_str).and_return('SHUT_RD')

          @client.shutdown(@dummy)

          @client.recv(1).should be_empty
        end

        it 'shuts down a socket for reading and writing' do
          @dummy.stub!(:to_str).and_return('RDWR')

          @client.shutdown(@dummy)

          @client.recv(1).should be_empty

          lambda { @client.write('hello') }.should raise_error(Errno::EPIPE)
        end
      end

      describe 'using an object that does not respond to #to_str' do
        it 'raises TypeError' do
          lambda { @server.shutdown(mock(:dummy)) }.should raise_error(TypeError)
        end
      end
    end
  end
end
