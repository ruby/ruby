require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'UDPSocket#recvfrom_nonblock' do
  SocketSpecs.each_ip_protocol do |family, ip_address, family_name|
    before do
      @server = UDPSocket.new(family)
      @client = UDPSocket.new(family)
    end

    after do
      @client.close
      @server.close
    end

    platform_is_not :windows do
      describe 'using an unbound socket' do
        it 'raises IO::WaitReadable' do
          lambda { @server.recvfrom_nonblock(1) }.should raise_error(IO::WaitReadable)
        end
      end
    end

    describe 'using a bound socket' do
      before do
        @server.bind(ip_address, 0)

        addr = @server.connect_address

        @client.connect(addr.ip_address, addr.ip_port)
      end

      describe 'without any data available' do
        it 'raises IO::WaitReadable' do
          lambda { @server.recvfrom_nonblock(1) }.should raise_error(IO::WaitReadable)
        end
      end

      platform_is_not :windows do
        describe 'with data available' do
          before do
            @client.write('hello')

            platform_is(:darwin, :freebsd) { IO.select([@server]) }
          end

          it 'returns an Array containing the data and an Array' do
            @server.recvfrom_nonblock(1).should be_an_instance_of(Array)
          end

          describe 'the returned Array' do
            before do
              @array = @server.recvfrom_nonblock(1)
            end

            it 'contains the data at index 0' do
              @array[0].should == 'h'
            end

            it 'contains an Array at index 1' do
              @array[1].should be_an_instance_of(Array)
            end
          end

          describe 'the returned address Array' do
            before do
              @addr = @server.recvfrom_nonblock(1)[1]
            end

            it 'uses the correct address family' do
              @addr[0].should == family_name
            end

            it 'uses the port of the client' do
              @addr[1].should == @client.local_address.ip_port
            end

            it 'uses the hostname of the client' do
              @addr[2].should == ip_address
            end

            it 'uses the IP address of the client' do
              @addr[3].should == ip_address
            end
          end
        end
      end
    end
  end
end
