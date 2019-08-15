require_relative '../spec_helper'

with_feature :unix_socket do
  describe 'UNIXSocket.socketpair' do
    before do
      @s1, @s2 = UNIXSocket.socketpair
    end

    after do
      @s1.close
      @s2.close
    end

    it 'returns two UNIXSockets' do
      @s1.should be_an_instance_of(UNIXSocket)
      @s2.should be_an_instance_of(UNIXSocket)
    end

    it 'connects the sockets to each other' do
      @s1.write('hello')

      @s2.recv(5).should == 'hello'
    end

    it 'sets the socket paths to empty Strings' do
      @s1.path.should == ''
      @s2.path.should == ''
    end

    it 'sets the socket addresses to empty Strings' do
      @s1.addr.should == ['AF_UNIX', '']
      @s2.addr.should == ['AF_UNIX', '']
    end

    it 'sets the socket peer addresses to empty Strings' do
      @s1.peeraddr.should == ['AF_UNIX', '']
      @s2.peeraddr.should == ['AF_UNIX', '']
    end
  end
end
