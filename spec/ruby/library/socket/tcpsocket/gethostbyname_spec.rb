require_relative '../spec_helper'
require_relative '../fixtures/classes'

# TODO: verify these for windows
describe "TCPSocket#gethostbyname" do
  before :each do
    suppress_warning do
      @host_info = TCPSocket.gethostbyname(SocketSpecs.hostname)
    end
  end

  it "returns an array elements of information on the hostname" do
    @host_info.should be_kind_of(Array)
  end

  platform_is_not :windows do
    it "returns the canonical name as first value" do
      @host_info[0].should == SocketSpecs.hostname
    end

    it "returns the address type as the third value" do
      address_type = @host_info[2]
      [Socket::AF_INET, Socket::AF_INET6].include?(address_type).should be_true
    end

    it "returns the IP address as the fourth value" do
      ip = @host_info[3]
      ["127.0.0.1", "::1"].include?(ip).should be_true
    end
  end

  platform_is :windows do
    quarantine! do # name lookup seems not working on Windows CI
      it "returns the canonical name as first value" do
        host = "#{ENV['COMPUTERNAME'].downcase}"
        host << ".#{ENV['USERDNSDOMAIN'].downcase}" if ENV['USERDNSDOMAIN']
        @host_info[0].should == host
      end
    end

    it "returns the address type as the third value" do
      @host_info[2].should == Socket::AF_INET
    end

    it "returns the IP address as the fourth value" do
      @host_info[3].should == "127.0.0.1"
    end
  end

  it "returns any aliases to the address as second value" do
    @host_info[1].should be_kind_of(Array)
  end
end

describe 'TCPSocket#gethostbyname' do
  it 'returns an Array' do
    suppress_warning do
      TCPSocket.gethostbyname('127.0.0.1').should be_an_instance_of(Array)
    end
  end

  describe 'using a hostname' do
    describe 'the returned Array' do
      before do
        suppress_warning do
          @array = TCPSocket.gethostbyname('127.0.0.1')
        end
      end

      it 'includes the canonical name as the 1st value' do
        @array[0].should == '127.0.0.1'
      end

      it 'includes an array of alternative hostnames as the 2nd value' do
        @array[1].should be_an_instance_of(Array)
      end

      it 'includes the address family as the 3rd value' do
        @array[2].should be_kind_of(Integer)
      end

      it 'includes the IP addresses as all the remaining values' do
        ips = %w{::1 127.0.0.1}

        ips.include?(@array[3]).should == true

        # Not all machines might have both IPv4 and IPv6 set up, so this value is
        # optional.
        ips.include?(@array[4]).should == true if @array[4]
      end
    end
  end

  SocketSpecs.each_ip_protocol do |family, ip_address|
    describe 'the returned Array' do
      before do
        suppress_warning do
          @array = TCPSocket.gethostbyname(ip_address)
        end
      end

      it 'includes the IP address as the 1st value' do
        @array[0].should == ip_address
      end

      it 'includes an empty list of aliases as the 2nd value' do
        @array[1].should == []
      end

      it 'includes the address family as the 3rd value' do
        @array[2].should == family
      end

      it 'includes the IP address as the 4th value' do
        @array[3].should == ip_address
      end
    end
  end
end
