require_relative '../spec_helper'
require_relative '../fixtures/classes'

platform_is_not :windows do
  describe "UNIXServer#accept" do
    before :each do
      @path = SocketSpecs.socket_path
      @server = UNIXServer.open(@path)
    end

    after :each do
      @server.close if @server
      SocketSpecs.rm_socket @path
    end

    it "accepts what is written by the client" do
      client = UNIXSocket.open(@path)

      client.send('hello', 0)

      sock = @server.accept
      begin
        data, info = sock.recvfrom(5)

        data.should == 'hello'
        info.should_not be_empty
      ensure
        sock.close
        client.close
      end
    end

    it "can be interrupted by Thread#kill" do
      t = Thread.new {
        @server.accept
      }
      Thread.pass while t.status and t.status != "sleep"

      # kill thread, ensure it dies in a reasonable amount of time
      t.kill
      a = 0
      while t.alive? and a < 5000
        sleep 0.001
        a += 1
      end
      a.should < 5000
    end

    it "can be interrupted by Thread#raise" do
      t = Thread.new {
        -> {
          @server.accept
        }.should raise_error(Exception, "interrupted")
      }

      Thread.pass while t.status and t.status != "sleep"
      t.raise Exception, "interrupted"
      t.join
    end
  end
end

with_feature :unix_socket do
  describe 'UNIXServer#accept' do
    before do
      @path = SocketSpecs.socket_path
      @server = UNIXServer.new(@path)
    end

    after do
      @server.close
      rm_r(@path)
    end

    describe 'without a client' do
      it 'blocks the calling thread' do
        lambda { @server.accept }.should block_caller
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
          @socket = @server.accept
          @socket.should be_an_instance_of(UNIXSocket)
        end
      end

      describe 'with data available' do
        before do
          @client.write('hello')
        end

        it 'returns a UNIXSocket' do
          @socket = @server.accept
          @socket.should be_an_instance_of(UNIXSocket)
        end

        describe 'the returned UNIXSocket' do
          it 'can read the data written' do
            @socket = @server.accept
            @socket.recv(5).should == 'hello'
          end
        end
      end
    end
  end
end
