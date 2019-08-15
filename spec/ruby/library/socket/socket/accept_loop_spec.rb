require_relative '../spec_helper'

describe 'Socket.accept_loop' do
  before do
    @server = Socket.new(:INET, :STREAM)
    @client = Socket.new(:INET, :STREAM)

    @server.bind(Socket.sockaddr_in(0, '127.0.0.1'))
    @server.listen(1)
  end

  after do
    @client.close
    @server.close
  end

  describe 'using an Array of Sockets' do
    describe 'without any available connections' do
      # FIXME windows randomly hangs here forever
      # https://ci.appveyor.com/project/ruby/ruby/builds/20817932/job/dor2ipny7ru4erpa
      platform_is_not :windows do
        it 'blocks the caller' do
          -> { Socket.accept_loop([@server]) }.should block_caller
        end
      end
    end

    describe 'with available connections' do
      before do
        @client.connect(@server.getsockname)
      end

      it 'yields a Socket and an Addrinfo' do
        conn = nil
        addr = nil

        Socket.accept_loop([@server]) do |connection, address|
          conn = connection
          addr = address
          break
        end

        begin
          conn.should be_an_instance_of(Socket)
          addr.should be_an_instance_of(Addrinfo)
        ensure
          conn.close
        end
      end
    end
  end

  describe 'using separate Socket arguments' do
    describe 'without any available connections' do
      it 'blocks the caller' do
        -> { Socket.accept_loop(@server) }.should block_caller
      end
    end

    describe 'with available connections' do
      before do
        @client.connect(@server.getsockname)
      end

      it 'yields a Socket and an Addrinfo' do
        conn = nil
        addr = nil

        Socket.accept_loop(@server) do |connection, address|
          conn = connection
          addr = address
          break
        end

        begin
          conn.should be_an_instance_of(Socket)
          addr.should be_an_instance_of(Addrinfo)
        ensure
          conn.close
        end
      end
    end
  end
end
