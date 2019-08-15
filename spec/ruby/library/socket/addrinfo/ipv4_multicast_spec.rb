require_relative '../spec_helper'

describe "Addrinfo#ipv4_multicast?" do
  it 'returns true for a multicast address' do
    Addrinfo.ip('224.0.0.0').ipv4_multicast?.should == true
    Addrinfo.ip('224.0.0.9').ipv4_multicast?.should == true
    Addrinfo.ip('239.255.255.250').ipv4_multicast?.should == true
  end

  it 'returns false for a regular address' do
    Addrinfo.ip('8.8.8.8').ipv4_multicast?.should == false
  end

  it 'returns false for an IPv6 address' do
    Addrinfo.ip('::1').ipv4_multicast?.should == false
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns false" do
        @addrinfo.ipv4_multicast?.should be_false
      end
    end
  end
end
