require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'TCPServer#initialize' do
  describe 'with a single Fixnum argument' do
    before do
      @server = TCPServer.new(0)
    end

    after do
      @server.close
    end

    it 'sets the port to the given argument' do
      @server.local_address.ip_port.should be_an_instance_of(Fixnum)
      @server.local_address.ip_port.should > 0
    end

    platform_is_not :windows do
      it 'sets the hostname to 0.0.0.0' do
        @server.local_address.ip_address.should == '0.0.0.0'
      end
    end

    it "sets the socket to binmode" do
      @server.binmode?.should be_true
    end
  end

  describe 'with a single String argument containing a numeric value' do
    before do
      @server = TCPServer.new('0')
    end

    after do
      @server.close
    end

    it 'sets the port to the given argument' do
      @server.local_address.ip_port.should be_an_instance_of(Fixnum)
      @server.local_address.ip_port.should > 0
    end

    platform_is_not :windows do
      it 'sets the hostname to 0.0.0.0' do
        @server.local_address.ip_address.should == '0.0.0.0'
      end
    end
  end

  describe 'with a single String argument containing a non numeric value' do
    it 'raises SocketError' do
      lambda { TCPServer.new('cats') }.should raise_error(SocketError)
    end
  end

  describe 'with a String and a Fixnum' do
    SocketSpecs.each_ip_protocol do |family, ip_address|
      before do
        @server = TCPServer.new(ip_address, 0)
      end

      after do
        @server.close
      end

      it 'sets the port to the given port argument' do
        @server.local_address.ip_port.should be_an_instance_of(Fixnum)
        @server.local_address.ip_port.should > 0
      end

      it 'sets the hostname to the given host argument' do
        @server.local_address.ip_address.should == ip_address
      end
    end
  end

  describe 'with a String and a custom object' do
    before do
      dummy = mock(:dummy)
      dummy.stub!(:to_str).and_return('0')

      @server = TCPServer.new('127.0.0.1', dummy)
    end

    after do
      @server.close
    end

    it 'sets the port to the given port argument' do
      @server.local_address.ip_port.should be_an_instance_of(Fixnum)
      @server.local_address.ip_port.should > 0
    end

    it 'sets the hostname to the given host argument' do
      @server.local_address.ip_address.should == '127.0.0.1'
    end
  end
end
