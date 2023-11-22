require_relative '../spec_helper'
require_relative 'shared/new'

with_feature :unix_socket do
  describe "UNIXSocket.new" do
    it_behaves_like :unixsocket_new, :new

    it "does not use the given block and warns to use UNIXSocket::open" do
      -> {
        @client = UNIXSocket.new(@path) { raise }
      }.should complain(/warning: UNIXSocket::new\(\) does not take block; use UNIXSocket::open\(\) instead/)
    end
  end
end
