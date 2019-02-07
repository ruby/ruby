require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket::IPSocket#getaddress" do

  it "returns the IP address of hostname" do
    addr_local = IPSocket.getaddress(SocketSpecs.hostname)
    ["127.0.0.1", "::1"].include?(addr_local).should == true
  end

  it "returns the IP address when passed an IP" do
    IPSocket.getaddress("127.0.0.1").should == "127.0.0.1"
    IPSocket.getaddress("0.0.0.0").should == "0.0.0.0"
    IPSocket.getaddress('::1').should == '::1'
  end

  # There is no way to make this fail-proof on all machines, because
  # DNS servers like opendns return A records for ANY host, including
  # traditionally invalidly named ones.
  it "raises an error on unknown hostnames" do
    lambda {
      IPSocket.getaddress("rubyspecdoesntexist.fallingsnow.net")
    }.should raise_error(SocketError)
  end
end
