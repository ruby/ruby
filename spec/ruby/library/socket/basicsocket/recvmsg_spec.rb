require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'BasicSocket#recvmsg' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    describe 'using a disconnected socket' do
      before do
        @client = Socket.new(family, :DGRAM)
        @server = Socket.new(family, :DGRAM)
      end

      after do
        @client.close
        @server.close
      end

      platform_is_not :windows do
        describe 'using an unbound socket' do
          it 'blocks the caller' do
            -> { @server.recvmsg }.should block_caller
          end
        end
      end

      describe 'using a bound socket' do
        before do
          @server.bind(Socket.sockaddr_in(0, ip_address))
        end

        describe 'without any data available' do
          it 'blocks the caller' do
            -> { @server.recvmsg }.should block_caller
          end
        end

        describe 'with data available' do
          before do
            @client.connect(@server.getsockname)

            @client.write('hello')
          end

          it 'returns an Array containing the data, an Addrinfo and the flags' do
            @server.recvmsg.should be_an_instance_of(Array)
          end

          describe 'without a maximum message length' do
            it 'reads all the available data' do
              @server.recvmsg[0].should == 'hello'
            end
          end

          describe 'with a maximum message length' do
            it 'reads up to the maximum amount of bytes' do
              @server.recvmsg(2)[0].should == 'he'
            end
          end

          describe 'the returned Array' do
            before do
              @array = @server.recvmsg
            end

            it 'stores the message at index 0' do
              @array[0].should == 'hello'
            end

            it 'stores an Addrinfo at index 1' do
              @array[1].should be_an_instance_of(Addrinfo)
            end

            platform_is_not :windows do
              it 'stores the flags at index 2' do
                @array[2].should be_kind_of(Integer)
              end
            end

            describe 'the returned Addrinfo' do
              before do
                @addr = @array[1]
              end

              it 'uses the IP address of the client' do
                @addr.ip_address.should == @client.local_address.ip_address
              end

              it 'uses the correct address family' do
                @addr.afamily.should == family
              end

              it 'uses the correct protocol family' do
                @addr.pfamily.should == family
              end

              it 'uses the correct socket type' do
                @addr.socktype.should == Socket::SOCK_DGRAM
              end

              it 'uses the port number of the client' do
                @addr.ip_port.should == @client.local_address.ip_port
              end
            end
          end
        end
      end
    end

    platform_is_not :windows do
      describe 'using a connected socket' do
        before do
          @client = Socket.new(family, :STREAM)
          @server = Socket.new(family, :STREAM)

          @server.bind(Socket.sockaddr_in(0, ip_address))
          @server.listen(1)

          @client.connect(@server.getsockname)
        end

        after do
          @client.close
          @server.close
        end

        describe 'without any data available' do
          it 'blocks the caller' do
            socket, _ = @server.accept
            begin
              -> { socket.recvmsg }.should block_caller
            ensure
              socket.close
            end
          end
        end

        describe 'with data available' do
          before do
            @client.write('hello')
            @socket, _ = @server.accept
          end

          after do
            @socket.close
          end

          it 'returns an Array containing the data, an Addrinfo and the flags' do
            @socket.recvmsg.should be_an_instance_of(Array)
          end

          describe 'the returned Array' do
            before do
              @array = @socket.recvmsg
            end

            it 'stores the message at index 0' do
              @array[0].should == 'hello'
            end

            it 'stores an Addrinfo at index 1' do
              @array[1].should be_an_instance_of(Addrinfo)
            end

            it 'stores the flags at index 2' do
              @array[2].should be_kind_of(Integer)
            end

            describe 'the returned Addrinfo' do
              before do
                @addr = @array[1]
              end

              it 'raises when receiving the ip_address message' do
                -> { @addr.ip_address }.should raise_error(SocketError)
              end

              it 'uses the correct address family' do
                @addr.afamily.should == Socket::AF_UNSPEC
              end

              it 'returns 0 for the protocol family' do
                @addr.pfamily.should == 0
              end

              it 'uses the correct socket type' do
                @addr.socktype.should == Socket::SOCK_STREAM
              end

              it 'raises when receiving the ip_port message' do
                -> { @addr.ip_port }.should raise_error(SocketError)
              end
            end
          end
        end
      end
    end
  end
end
