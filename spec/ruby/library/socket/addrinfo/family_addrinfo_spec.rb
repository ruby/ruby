require_relative '../spec_helper'

describe 'Addrinfo#family_addrinfo' do
  it 'raises ArgumentError if no arguments are given' do
    addr = Addrinfo.tcp('127.0.0.1', 0)

    -> { addr.family_addrinfo }.should raise_error(ArgumentError)
  end

  describe 'using multiple arguments' do
    describe 'with an IP Addrinfo' do
      before do
        @source = Addrinfo.tcp('127.0.0.1', 0)
      end

      it 'raises ArgumentError if only 1 argument is given' do
        -> { @source.family_addrinfo('127.0.0.1') }.should raise_error(ArgumentError)
      end

      it 'raises ArgumentError if more than 2 arguments are given' do
        -> { @source.family_addrinfo('127.0.0.1', 0, 666) }.should raise_error(ArgumentError)
      end

      it 'returns an Addrinfo when a host and port are given' do
        addr = @source.family_addrinfo('127.0.0.1', 0)

        addr.should be_an_instance_of(Addrinfo)
      end

      describe 'the returned Addrinfo' do
        before do
          @addr = @source.family_addrinfo('127.0.0.1', 0)
        end

        it 'uses the same address family as the source Addrinfo' do
          @addr.afamily.should == @source.afamily
        end

        it 'uses the same protocol family as the source Addrinfo' do
          @addr.pfamily.should == @source.pfamily
        end

        it 'uses the same socket type as the source Addrinfo' do
          @addr.socktype.should == @source.socktype
        end

        it 'uses the same protocol as the source Addrinfo' do
          @addr.protocol.should == @source.protocol
        end
      end
    end

    with_feature :unix_socket do
      describe 'with a UNIX Addrinfo' do
        before do
          @source = Addrinfo.unix('cats')
        end

        it 'raises ArgumentError if more than 1 argument is given' do
          -> { @source.family_addrinfo('foo', 'bar') }.should raise_error(ArgumentError)
        end

        it 'returns an Addrinfo when a UNIX socket path is given' do
          addr = @source.family_addrinfo('dogs')

          addr.should be_an_instance_of(Addrinfo)
        end

        describe 'the returned Addrinfo' do
          before do
            @addr = @source.family_addrinfo('dogs')
          end

          it 'uses AF_UNIX as the address family' do
            @addr.afamily.should == Socket::AF_UNIX
          end

          it 'uses PF_UNIX as the protocol family' do
            @addr.pfamily.should == Socket::PF_UNIX
          end

          it 'uses the given socket path' do
            @addr.unix_path.should == 'dogs'
          end
        end
      end
    end
  end

  describe 'using an Addrinfo as the 1st argument' do
    before do
      @source = Addrinfo.tcp('127.0.0.1', 0)
    end

    it 'returns the input Addrinfo' do
      input = Addrinfo.tcp('127.0.0.2', 0)
      @source.family_addrinfo(input).should == input
    end

    it 'raises ArgumentError if more than 1 argument is given' do
      input = Addrinfo.tcp('127.0.0.2', 0)
      -> { @source.family_addrinfo(input, 666) }.should raise_error(ArgumentError)
    end

    it "raises ArgumentError if the protocol families don't match" do
      input = Addrinfo.tcp('::1', 0)
      -> { @source.family_addrinfo(input) }.should raise_error(ArgumentError)
    end

    it "raises ArgumentError if the socket types don't match" do
      input = Addrinfo.udp('127.0.0.1', 0)
      -> { @source.family_addrinfo(input) }.should raise_error(ArgumentError)
    end
  end
end
