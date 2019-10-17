require_relative '../spec_helper'

describe 'Socket.ip_address_list' do
  it 'returns an Array' do
    Socket.ip_address_list.should be_an_instance_of(Array)
  end

  describe 'the returned Array' do
    before do
      @array = Socket.ip_address_list
    end

    it 'is not empty' do
      @array.should_not be_empty
    end

    it 'contains Addrinfo objects' do
      @array.each do |klass|
        klass.should be_an_instance_of(Addrinfo)
      end
    end
  end

  describe 'each returned Addrinfo' do
    before do
      @array = Socket.ip_address_list
    end

    it 'has a non-empty IP address' do
      @array.each do |addr|
        addr.ip_address.should be_an_instance_of(String)
        addr.ip_address.should_not be_empty
      end
    end

    it 'has an address family' do
      families = [Socket::AF_INET, Socket::AF_INET6]

      @array.each do |addr|
        families.include?(addr.afamily).should == true
      end
    end

    it 'uses 0 as the port number' do
      @array.each do |addr|
        addr.ip_port.should == 0
      end
    end
  end
end
