require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe "UNIXServer#accept_nonblock" do
    before :each do
      @path = SocketSpecs.socket_path
      @server = UNIXServer.open(@path)
      @client = UNIXSocket.open(@path)

      @socket = @server.accept_nonblock
      @client.send("foobar", 0)
    end

    after :each do
      @socket.close
      @client.close
      @server.close
      SocketSpecs.rm_socket @path
    end

    it "accepts a connection in a non-blocking way" do
      data = @socket.recvfrom(6).first
      data.should == "foobar"
    end

    it "returns a UNIXSocket" do
      @socket.should be_kind_of(UNIXSocket)
    end

    it 'returns :wait_readable in exceptionless mode' do
      @server.accept_nonblock(exception: false).should == :wait_readable
    end
  end

  describe 'UNIXServer#accept_nonblock' do
    before do
      @path   = SocketSpecs.socket_path
      @server = UNIXServer.new(@path)
    end

    after do
      @server.close
      rm_r(@path)
    end

    describe 'without a client' do
      it 'raises IO::WaitReadable' do
        -> { @server.accept_nonblock }.should raise_error(IO::WaitReadable)
      end
    end

    describe 'with a client' do
      before do
        @client = UNIXSocket.new(@path)
      end

      after do
        @client.close
        @socket.close if @socket
      end

      describe 'without any data' do
        it 'returns a UNIXSocket' do
          @socket = @server.accept_nonblock
          @socket.should be_an_instance_of(UNIXSocket)
        end
      end

      describe 'with data available' do
        before do
          @client.write('hello')
        end

        it 'returns a UNIXSocket' do
          @socket = @server.accept_nonblock
          @socket.should be_an_instance_of(UNIXSocket)
        end

        describe 'the returned UNIXSocket' do
          it 'can read the data written' do
            @socket = @server.accept_nonblock
            @socket.recv(5).should == 'hello'
          end
        end
      end
    end
  end
end
