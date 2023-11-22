require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe "UNIXSocket#inspect" do
    it "returns sockets fd for unnamed sockets" do
      begin
        s1, s2 = UNIXSocket.socketpair
        s1.inspect.should == "#<UNIXSocket:fd #{s1.fileno}>"
        s2.inspect.should == "#<UNIXSocket:fd #{s2.fileno}>"
      ensure
        s1.close
        s2.close
      end
    end
  end
end
