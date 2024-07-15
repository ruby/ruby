require_relative '../spec_helper'
require_relative '../fixtures/classes'
require_relative '../shared/partially_closable_sockets'
require_relative 'shared/pair'

with_feature :unix_socket do
  describe "UNIXSocket.socketpair" do
    it_should_behave_like :unixsocket_pair
    it_should_behave_like :partially_closable_sockets

    before :each do
      @s1, @s2 = UNIXSocket.socketpair
    end

    after :each do
      @s1.close
      @s2.close
    end
  end
end
