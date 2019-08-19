require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket#getservbyname" do
  it "returns the port for service 'discard'" do
    Socket.getservbyname('discard').should == 9
  end

  it "returns the port for service 'discard' with protocol 'tcp'" do
    Socket.getservbyname('discard', 'tcp').should == 9
  end

  it 'returns the port for service "http"' do
    Socket.getservbyname('http').should == 80
  end

  it 'returns the port for service "http" with protocol "tcp"' do
    Socket.getservbyname('http', 'tcp').should == 80
  end

  it "returns the port for service 'domain' with protocol 'udp'" do
    Socket.getservbyname('domain', 'udp').should == 53
  end

  it "returns the port for service 'daytime'" do
    Socket.getservbyname('daytime').should == 13
  end

  it "raises a SocketError when the service or port is invalid" do
    lambda { Socket.getservbyname('invalid') }.should raise_error(SocketError)
  end
end
