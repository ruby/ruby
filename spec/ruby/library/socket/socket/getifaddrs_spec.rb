require_relative '../spec_helper'

platform_is_not :aix, :"solaris2.10" do
describe 'Socket.getifaddrs' do
  before do
    @ifaddrs = Socket.getifaddrs
  end

  it 'returns an Array' do
    @ifaddrs.should be_an_instance_of(Array)
  end

  describe 'the returned Array' do
    it 'should not be empty' do
      @ifaddrs.should_not be_empty
    end

    it 'contains instances of Socket::Ifaddr' do
      @ifaddrs.each do |ifaddr|
        ifaddr.should be_an_instance_of(Socket::Ifaddr)
      end
    end
  end

  describe 'each returned Socket::Ifaddr' do
    it 'has an interface index' do
      @ifaddrs.each do |ifaddr|
        ifaddr.ifindex.should be_an_instance_of(Fixnum)
      end
    end

    it 'has an interface name' do
      @ifaddrs.each do |ifaddr|
        ifaddr.name.should be_an_instance_of(String)
      end
    end

    it 'has a set of flags' do
      @ifaddrs.each do |ifaddr|
        ifaddr.flags.should be_an_instance_of(Fixnum)
      end
    end
  end

  describe 'the Socket::Ifaddr address' do
    before do
      @addrs = @ifaddrs.map(&:addr).compact
    end

    it 'is an Addrinfo' do
      @addrs.each do |addr|
        addr.should be_an_instance_of(Addrinfo)
      end
    end

    it 'has an address family' do
      @addrs.each do |addr|
        addr.afamily.should be_an_instance_of(Fixnum)
        addr.afamily.should_not == Socket::AF_UNSPEC
      end
    end
  end

  platform_is_not :windows do
    describe 'the Socket::Ifaddr broadcast address' do
      before do
        @addrs = @ifaddrs.map(&:broadaddr).compact
      end

      it 'is an Addrinfo' do
        @addrs.each do |addr|
          addr.should be_an_instance_of(Addrinfo)
        end
      end

      it 'has an address family' do
        @addrs.each do |addr|
          addr.afamily.should be_an_instance_of(Fixnum)
          addr.afamily.should_not == Socket::AF_UNSPEC
        end
      end
    end

    describe 'the Socket::Ifaddr netmask address' do
      before do
        @addrs = @ifaddrs.map(&:netmask).compact.select(&:ip?)
      end

      it 'is an Addrinfo' do
        @addrs.each do |addr|
          addr.should be_an_instance_of(Addrinfo)
        end
      end

      it 'has an address family' do
        @addrs.each do |addr|
          addr.afamily.should be_an_instance_of(Fixnum)
          addr.afamily.should_not == Socket::AF_UNSPEC
        end
      end

      it 'has an IP address' do
        @addrs.each do |addr|
          addr.ip_address.should be_an_instance_of(String)
        end
      end
    end
  end
end
end
