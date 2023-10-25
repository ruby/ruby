require_relative '../spec_helper'
require_relative '../fixtures/classes'
require 'ipaddr'

describe 'Socket.gethostbyaddr' do
  describe 'using an IPv4 address' do
    before do
      @addr = IPAddr.new('127.0.0.1').hton
    end

    describe 'without an explicit address family' do
      it 'returns an Array' do
        suppress_warning { Socket.gethostbyaddr(@addr) }.should be_an_instance_of(Array)
      end

      describe 'the returned Array' do
        before do
          @array = suppress_warning { Socket.gethostbyaddr(@addr) }
        end

        # RubyCI Solaris 11x defines 127.0.0.1 as unstable11x
        platform_is_not :"solaris2.11" do
          it 'includes the hostname as the first value' do
            @array[0].should == SocketSpecs.hostname_reverse_lookup
          end
        end

        it 'includes the aliases as the 2nd value' do
          @array[1].should be_an_instance_of(Array)

          @array[1].each do |val|
            val.should be_an_instance_of(String)
          end
        end

        it 'includes the address type as the 3rd value' do
          @array[2].should == Socket::AF_INET
        end

        it 'includes all address strings as the remaining values' do
          @array[3].should == @addr

          @array[4..-1].each do |val|
            val.should be_an_instance_of(String)
          end
        end
      end
    end

    describe 'with an explicit address family' do
      it 'returns an Array when using an Integer as the address family' do
        suppress_warning { Socket.gethostbyaddr(@addr, Socket::AF_INET) }.should be_an_instance_of(Array)
      end

      it 'returns an Array when using a Symbol as the address family' do
        suppress_warning { Socket.gethostbyaddr(@addr, :INET) }.should be_an_instance_of(Array)
      end

      it 'raises SocketError when the address is not supported by the family' do
        -> { suppress_warning { Socket.gethostbyaddr(@addr, :INET6) } }.should raise_error(SocketError)
      end
    end
  end

  guard -> { SocketSpecs.ipv6_available? && platform_is_not(:aix) } do
    describe 'using an IPv6 address' do
      before do
        @addr = IPAddr.new('::1').hton
      end

      describe 'without an explicit address family' do
        it 'returns an Array' do
          suppress_warning { Socket.gethostbyaddr(@addr) }.should be_an_instance_of(Array)
        end

        describe 'the returned Array' do
          before do
            @array = suppress_warning { Socket.gethostbyaddr(@addr) }
          end

          it 'includes the hostname as the first value' do
            @array[0].should == SocketSpecs.hostname_reverse_lookup("::1")
          end

          it 'includes the aliases as the 2nd value' do
            @array[1].should be_an_instance_of(Array)

            @array[1].each do |val|
              val.should be_an_instance_of(String)
            end
          end

          it 'includes the address type as the 3rd value' do
            @array[2].should == Socket::AF_INET6
          end

          it 'includes all address strings as the remaining values' do
            @array[3].should be_an_instance_of(String)

            @array[4..-1].each do |val|
              val.should be_an_instance_of(String)
            end
          end
        end
      end

      describe 'with an explicit address family' do
        it 'returns an Array when using an Integer as the address family' do
          suppress_warning { Socket.gethostbyaddr(@addr, Socket::AF_INET6) }.should be_an_instance_of(Array)
        end

        it 'returns an Array when using a Symbol as the address family' do
          suppress_warning { Socket.gethostbyaddr(@addr, :INET6) }.should be_an_instance_of(Array)
        end

        platform_is_not :windows, :wsl do
          it 'raises SocketError when the address is not supported by the family' do
            -> { suppress_warning { Socket.gethostbyaddr(@addr, :INET) } }.should raise_error(SocketError)
          end
        end
      end
    end
  end
end
