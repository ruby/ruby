describe :socket_socketpair, shared: true do
  platform_is_not :windows do
    it "ensures the returned sockets are connected" do
      s1, s2 = Socket.public_send(@method, Socket::AF_UNIX, 1, 0)
      s1.puts("test")
      s2.gets.should == "test\n"
      s1.close
      s2.close
    end

    it "responses with array of two sockets" do
      begin
        s1, s2 = Socket.public_send(@method, :UNIX, :STREAM)

        s1.should be_an_instance_of(Socket)
        s2.should be_an_instance_of(Socket)
      ensure
        s1.close
        s2.close
      end
    end

    describe 'using an Integer as the 1st and 2nd argument' do
      it 'returns two Socket objects' do
        s1, s2 = Socket.public_send(@method, Socket::AF_UNIX, Socket::SOCK_STREAM)

        s1.should be_an_instance_of(Socket)
        s2.should be_an_instance_of(Socket)
        s1.close
        s2.close
      end
    end

    describe 'using a Symbol as the 1st and 2nd argument' do
      it 'returns two Socket objects' do
        s1, s2 = Socket.public_send(@method, :UNIX, :STREAM)

        s1.should be_an_instance_of(Socket)
        s2.should be_an_instance_of(Socket)
        s1.close
        s2.close
      end

      it 'raises SocketError for an unknown address family' do
        -> { Socket.public_send(@method, :CATS, :STREAM) }.should raise_error(SocketError)
      end

      it 'raises SocketError for an unknown socket type' do
        -> { Socket.public_send(@method, :UNIX, :CATS) }.should raise_error(SocketError)
      end
    end

    describe 'using a String as the 1st and 2nd argument' do
      it 'returns two Socket objects' do
        s1, s2 = Socket.public_send(@method, 'UNIX', 'STREAM')

        s1.should be_an_instance_of(Socket)
        s2.should be_an_instance_of(Socket)
        s1.close
        s2.close
      end

      it 'raises SocketError for an unknown address family' do
        -> { Socket.public_send(@method, 'CATS', 'STREAM') }.should raise_error(SocketError)
      end

      it 'raises SocketError for an unknown socket type' do
        -> { Socket.public_send(@method, 'UNIX', 'CATS') }.should raise_error(SocketError)
      end
    end

    describe 'using an object that responds to #to_str as the 1st and 2nd argument' do
      it 'returns two Socket objects' do
        family = mock(:family)
        type   = mock(:type)

        family.stub!(:to_str).and_return('UNIX')
        type.stub!(:to_str).and_return('STREAM')

        s1, s2 = Socket.public_send(@method, family, type)

        s1.should be_an_instance_of(Socket)
        s2.should be_an_instance_of(Socket)
        s1.close
        s2.close
      end

      it 'raises TypeError when #to_str does not return a String' do
        family = mock(:family)
        type   = mock(:type)

        family.stub!(:to_str).and_return(Socket::AF_UNIX)
        type.stub!(:to_str).and_return(Socket::SOCK_STREAM)

        -> { Socket.public_send(@method, family, type) }.should raise_error(TypeError)
      end

      it 'raises SocketError for an unknown address family' do
        family = mock(:family)
        type   = mock(:type)

        family.stub!(:to_str).and_return('CATS')
        type.stub!(:to_str).and_return('STREAM')

        -> { Socket.public_send(@method, family, type) }.should raise_error(SocketError)
      end

      it 'raises SocketError for an unknown socket type' do
        family = mock(:family)
        type   = mock(:type)

        family.stub!(:to_str).and_return('UNIX')
        type.stub!(:to_str).and_return('CATS')

        -> { Socket.public_send(@method, family, type) }.should raise_error(SocketError)
      end
    end

    it 'accepts a custom protocol as an Integer as the 3rd argument' do
      s1, s2 = Socket.public_send(@method, :UNIX, :STREAM, Socket::IPPROTO_IP)
      s1.should be_an_instance_of(Socket)
      s2.should be_an_instance_of(Socket)
      s1.close
      s2.close
    end

    it 'connects the returned Socket objects' do
      s1, s2 = Socket.public_send(@method, :UNIX, :STREAM)
      begin
        s1.write('hello')
        s2.recv(5).should == 'hello'
      ensure
        s1.close
        s2.close
      end
    end
  end
end
