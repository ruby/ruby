# -*- encoding: binary -*-
require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket#gethostbyname" do
  it "returns broadcast address info for '<broadcast>'" do
    addr = Socket.gethostbyname('<broadcast>');
    addr.should == ["255.255.255.255", [], 2, "\377\377\377\377"]
  end

  it "returns broadcast address info for '<any>'" do
    addr = Socket.gethostbyname('<any>');
    addr.should == ["0.0.0.0", [], 2, "\000\000\000\000"]
  end
end

describe 'Socket.gethostbyname' do
  it 'returns an Array' do
    Socket.gethostbyname('127.0.0.1').should be_an_instance_of(Array)
  end

  describe 'the returned Array' do
    before do
      @array = Socket.gethostbyname('127.0.0.1')
    end

    it 'includes the hostname as the first value' do
      @array[0].should == '127.0.0.1'
    end

    it 'includes the aliases as the 2nd value' do
      @array[1].should be_an_instance_of(Array)

      @array[1].each do |val|
        val.should be_an_instance_of(String)
      end
    end

    it 'includes the address type as the 3rd value' do
      possible = [Socket::AF_INET, Socket::AF_INET6]

      possible.include?(@array[2]).should == true
    end

    it 'includes the address strings as the remaining values' do
      @array[3].should be_an_instance_of(String)

      @array[4..-1].each do |val|
        val.should be_an_instance_of(String)
      end
    end
  end

  describe 'using <broadcast> as the input address' do
    describe 'the returned Array' do
      before do
        @addr = Socket.gethostbyname('<broadcast>')
      end

      it 'includes the broadcast address as the first value' do
        @addr[0].should == '255.255.255.255'
      end

      it 'includes the address type as the 3rd value' do
        @addr[2].should == Socket::AF_INET
      end

      it 'includes the address string as the 4th value' do
        @addr[3].should == [255, 255, 255, 255].pack('C4')
      end
    end
  end

  describe 'using <any> as the input address' do
    describe 'the returned Array' do
      before do
        @addr = Socket.gethostbyname('<any>')
      end

      it 'includes the wildcard address as the first value' do
        @addr[0].should == '0.0.0.0'
      end

      it 'includes the address type as the 3rd value' do
        @addr[2].should == Socket::AF_INET
      end

      it 'includes the address string as the 4th value' do
        @addr[3].should == [0, 0, 0, 0].pack('C4')
      end
    end
  end

  describe 'using an IPv4 address' do
    describe 'the returned Array' do
      before do
        @addr = Socket.gethostbyname('127.0.0.1')
      end

      it 'includes the IP address as the first value' do
        @addr[0].should == '127.0.0.1'
      end

      it 'includes the address type as the 3rd value' do
        @addr[2].should == Socket::AF_INET
      end

      it 'includes the address string as the 4th value' do
        @addr[3].should == [127, 0, 0, 1].pack('C4')
      end
    end
  end

  guard -> { SocketSpecs.ipv6_available? } do
    describe 'using an IPv6 address' do
      describe 'the returned Array' do
        before do
          @addr = Socket.gethostbyname('::1')
        end

        it 'includes the IP address as the first value' do
          @addr[0].should == '::1'
        end

        it 'includes the address type as the 3rd value' do
          @addr[2].should == Socket::AF_INET6
        end

        it 'includes the address string as the 4th value' do
          @addr[3].should == [0, 0, 0, 0, 0, 0, 0, 1].pack('n8')
        end
      end
    end
  end
end
