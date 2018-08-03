require_relative '../spec_helper'

describe 'Socket.getservbyport' do
  platform_is_not :windows do
    it 'returns the service name as a String' do
      Socket.getservbyport(514).should == 'shell'
    end
  end

  platform_is :windows do
    it 'returns the service name as a String' do
      Socket.getservbyport(514).should == 'cmd'
    end
  end

  it 'returns the service name when using a custom protocol name' do
    Socket.getservbyport(514, 'udp').should == 'syslog'
  end

  it 'raises SocketError for an unknown port number' do
    lambda { Socket.getservbyport(0) }.should raise_error(SocketError)
  end
end
