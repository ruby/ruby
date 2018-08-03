require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket.getaddrinfo" do
  before :each do
    @do_not_reverse_lookup = BasicSocket.do_not_reverse_lookup
    BasicSocket.do_not_reverse_lookup = true
  end

  after :each do
    BasicSocket.do_not_reverse_lookup = @do_not_reverse_lookup
  end

  platform_is_not :solaris, :windows do
    it "gets the address information" do
      expected = []
      # The check for AP_INET6's class is needed because ipaddr.rb adds
      # fake AP_INET6 even in case when IPv6 is not really supported.
      # Without such check, this test might fail when ipaddr was required
      # by some other specs.
      if (Socket.constants.include? 'AF_INET6') &&
        (Socket::AF_INET6.class != Object) then
        expected.concat [
          ['AF_INET6', 9, SocketSpecs.hostname, '::1', Socket::AF_INET6,
            Socket::SOCK_DGRAM, Socket::IPPROTO_UDP],
            ['AF_INET6', 9, SocketSpecs.hostname, '::1', Socket::AF_INET6,
              Socket::SOCK_STREAM, Socket::IPPROTO_TCP],
              ['AF_INET6', 9, SocketSpecs.hostname, 'fe80::1%lo0', Socket::AF_INET6,
                Socket::SOCK_DGRAM, Socket::IPPROTO_UDP],
                ['AF_INET6', 9, SocketSpecs.hostname, 'fe80::1%lo0', Socket::AF_INET6,
                  Socket::SOCK_STREAM, Socket::IPPROTO_TCP],
        ]
      end

      expected.concat [
        ['AF_INET', 9, SocketSpecs.hostname, '127.0.0.1', Socket::AF_INET,
          Socket::SOCK_DGRAM, Socket::IPPROTO_UDP],
          ['AF_INET', 9, SocketSpecs.hostname, '127.0.0.1', Socket::AF_INET,
            Socket::SOCK_STREAM, Socket::IPPROTO_TCP],
      ]

      addrinfo = Socket.getaddrinfo SocketSpecs.hostname, 'discard'
      addrinfo.each do |a|
        case a.last
        when Socket::IPPROTO_UDP, Socket::IPPROTO_TCP
          expected.should include(a)
        else
          # don't check this. It's some weird protocol we don't know about
          # so we can't spec it.
        end
      end
    end

    # #getaddrinfo will return a INADDR_ANY address (0.0.0.0 or "::")
    # if it's a passive socket. In the case of non-passive
    # sockets (AI_PASSIVE not set) it should return the loopback
    # address (127.0.0.1 or "::1").

    it "accepts empty addresses for IPv4 passive sockets" do
      res = Socket.getaddrinfo(nil, "discard",
                               Socket::AF_INET,
                               Socket::SOCK_STREAM,
                               Socket::IPPROTO_TCP,
                               Socket::AI_PASSIVE)

      expected = [["AF_INET", 9, "0.0.0.0", "0.0.0.0", Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP]]
      res.should == expected
    end

    it "accepts empty addresses for IPv4 non-passive sockets" do
      res = Socket.getaddrinfo(nil, "discard",
                               Socket::AF_INET,
                               Socket::SOCK_STREAM,
                               Socket::IPPROTO_TCP,
                               0)

      expected = [["AF_INET", 9, "127.0.0.1", "127.0.0.1", Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP]]
      res.should == expected
    end


    it "accepts empty addresses for IPv6 passive sockets" do
      res = Socket.getaddrinfo(nil, "discard",
                               Socket::AF_INET6,
                               Socket::SOCK_STREAM,
                               Socket::IPPROTO_TCP,
                               Socket::AI_PASSIVE)

      expected = [
        ["AF_INET6", 9, "::", "::", Socket::AF_INET6, Socket::SOCK_STREAM, Socket::IPPROTO_TCP],
        ["AF_INET6", 9, "0:0:0:0:0:0:0:0", "0:0:0:0:0:0:0:0", Socket::AF_INET6, Socket::SOCK_STREAM, Socket::IPPROTO_TCP]
      ]
      res.each { |a| expected.should include(a) }
    end

    it "accepts empty addresses for IPv6 non-passive sockets" do
      res = Socket.getaddrinfo(nil, "discard",
                               Socket::AF_INET6,
                               Socket::SOCK_STREAM,
                               Socket::IPPROTO_TCP,
                               0)

      expected = [
        ["AF_INET6", 9, "::1", "::1", Socket::AF_INET6, Socket::SOCK_STREAM, Socket::IPPROTO_TCP],
        ["AF_INET6", 9, "0:0:0:0:0:0:0:1", "0:0:0:0:0:0:0:1", Socket::AF_INET6, Socket::SOCK_STREAM, Socket::IPPROTO_TCP]
      ]
      res.each { |a| expected.should include(a) }
    end
  end
end

describe 'Socket.getaddrinfo' do
  describe 'without global reverse lookups' do
    it 'returns an Array' do
      Socket.getaddrinfo(nil, 'http').should be_an_instance_of(Array)
    end

    it 'accepts a Fixnum as the address family' do
      array = Socket.getaddrinfo(nil, 'http', Socket::AF_INET)[0]

      array[0].should == 'AF_INET'
      array[1].should == 80
      array[2].should == '127.0.0.1'
      array[3].should == '127.0.0.1'
      array[4].should == Socket::AF_INET
      array[5].should be_an_instance_of(Fixnum)
      array[6].should be_an_instance_of(Fixnum)
    end

    it 'accepts a Fixnum as the address family using IPv6' do
      array = Socket.getaddrinfo(nil, 'http', Socket::AF_INET6)[0]

      array[0].should == 'AF_INET6'
      array[1].should == 80
      array[2].should == '::1'
      array[3].should == '::1'
      array[4].should == Socket::AF_INET6
      array[5].should be_an_instance_of(Fixnum)
      array[6].should be_an_instance_of(Fixnum)
    end

    it 'accepts a Symbol as the address family' do
      array = Socket.getaddrinfo(nil, 'http', :INET)[0]

      array[0].should == 'AF_INET'
      array[1].should == 80
      array[2].should == '127.0.0.1'
      array[3].should == '127.0.0.1'
      array[4].should == Socket::AF_INET
      array[5].should be_an_instance_of(Fixnum)
      array[6].should be_an_instance_of(Fixnum)
    end

    it 'accepts a Symbol as the address family using IPv6' do
      array = Socket.getaddrinfo(nil, 'http', :INET6)[0]

      array[0].should == 'AF_INET6'
      array[1].should == 80
      array[2].should == '::1'
      array[3].should == '::1'
      array[4].should == Socket::AF_INET6
      array[5].should be_an_instance_of(Fixnum)
      array[6].should be_an_instance_of(Fixnum)
    end

    it 'accepts a String as the address family' do
      array = Socket.getaddrinfo(nil, 'http', 'INET')[0]

      array[0].should == 'AF_INET'
      array[1].should == 80
      array[2].should == '127.0.0.1'
      array[3].should == '127.0.0.1'
      array[4].should == Socket::AF_INET
      array[5].should be_an_instance_of(Fixnum)
      array[6].should be_an_instance_of(Fixnum)
    end

    it 'accepts a String as the address family using IPv6' do
      array = Socket.getaddrinfo(nil, 'http', 'INET6')[0]

      array[0].should == 'AF_INET6'
      array[1].should == 80
      array[2].should == '::1'
      array[3].should == '::1'
      array[4].should == Socket::AF_INET6
      array[5].should be_an_instance_of(Fixnum)
      array[6].should be_an_instance_of(Fixnum)
    end

    it 'accepts an object responding to #to_str as the host' do
      dummy = mock(:dummy)

      dummy.stub!(:to_str).and_return('127.0.0.1')

      array = Socket.getaddrinfo(dummy, 'http')[0]

      array[0].should == 'AF_INET'
      array[1].should == 80
      array[2].should == '127.0.0.1'
      array[3].should == '127.0.0.1'
      array[4].should == Socket::AF_INET
      array[5].should be_an_instance_of(Fixnum)
      array[6].should be_an_instance_of(Fixnum)
    end

    it 'accepts an object responding to #to_str as the address family' do
      dummy = mock(:dummy)

      dummy.stub!(:to_str).and_return('INET')

      array = Socket.getaddrinfo(nil, 'http', dummy)[0]

      array[0].should == 'AF_INET'
      array[1].should == 80
      array[2].should == '127.0.0.1'
      array[3].should == '127.0.0.1'
      array[4].should == Socket::AF_INET
      array[5].should be_an_instance_of(Fixnum)
      array[6].should be_an_instance_of(Fixnum)
    end

    ipproto_tcp = Socket::IPPROTO_TCP
    platform_is :windows do
      ipproto_tcp = 0
    end

    it 'accepts a Fixnum as the socket type' do
      Socket.getaddrinfo(nil, 'http', :INET, Socket::SOCK_STREAM)[0].should == [
        'AF_INET',
        80,
        '127.0.0.1',
        '127.0.0.1',
        Socket::AF_INET,
        Socket::SOCK_STREAM,
        ipproto_tcp
      ]
    end

    it 'accepts a Symbol as the socket type' do
      Socket.getaddrinfo(nil, 'http', :INET, :STREAM)[0].should == [
        'AF_INET',
        80,
        '127.0.0.1',
        '127.0.0.1',
        Socket::AF_INET,
        Socket::SOCK_STREAM,
        ipproto_tcp
      ]
    end

    it 'accepts a String as the socket type' do
      Socket.getaddrinfo(nil, 'http', :INET, 'STREAM')[0].should == [
        'AF_INET',
        80,
        '127.0.0.1',
        '127.0.0.1',
        Socket::AF_INET,
        Socket::SOCK_STREAM,
        ipproto_tcp
      ]
    end

    it 'accepts an object responding to #to_str as the socket type' do
      dummy = mock(:dummy)

      dummy.stub!(:to_str).and_return('STREAM')

      Socket.getaddrinfo(nil, 'http', :INET, dummy)[0].should == [
        'AF_INET',
        80,
        '127.0.0.1',
        '127.0.0.1',
        Socket::AF_INET,
        Socket::SOCK_STREAM,
        ipproto_tcp
      ]
    end

    platform_is_not :windows do
      it 'accepts a Fixnum as the protocol family' do
        addr = Socket.getaddrinfo(nil, 'http', :INET, :DGRAM, Socket::IPPROTO_UDP)

        addr[0].should == [
          'AF_INET',
          80,
          '127.0.0.1',
          '127.0.0.1',
          Socket::AF_INET,
          Socket::SOCK_DGRAM,
          Socket::IPPROTO_UDP
        ]
      end
    end

    it 'accepts a Fixnum as the flags' do
      addr = Socket.getaddrinfo(nil, 'http', :INET, :STREAM,
                                Socket::IPPROTO_TCP, Socket::AI_PASSIVE)

      addr[0].should == [
        'AF_INET',
        80,
        '0.0.0.0',
        '0.0.0.0',
        Socket::AF_INET,
        Socket::SOCK_STREAM,
        Socket::IPPROTO_TCP
      ]
    end

    it 'performs a reverse lookup when the reverse_lookup argument is true' do
      addr = Socket.getaddrinfo(nil, 'http', :INET, :STREAM,
                                Socket::IPPROTO_TCP, 0, true)[0]

      addr[0].should == 'AF_INET'
      addr[1].should == 80

      addr[2].should be_an_instance_of(String)
      addr[2].should_not == addr[3]

      addr[3].should == '127.0.0.1'
    end

    it 'performs a reverse lookup when the reverse_lookup argument is :hostname' do
      addr = Socket.getaddrinfo(nil, 'http', :INET, :STREAM,
                                Socket::IPPROTO_TCP, 0, :hostname)[0]

      addr[0].should == 'AF_INET'
      addr[1].should == 80

      addr[2].should be_an_instance_of(String)
      addr[2].should_not == addr[3]

      addr[3].should == '127.0.0.1'
    end

    it 'performs a reverse lookup when the reverse_lookup argument is :numeric' do
      addr = Socket.getaddrinfo(nil, 'http', :INET, :STREAM,
                                Socket::IPPROTO_TCP, 0, :numeric)[0]

      addr.should == [
        'AF_INET',
        80,
        '127.0.0.1',
        '127.0.0.1',
        Socket::AF_INET,
        Socket::SOCK_STREAM,
        Socket::IPPROTO_TCP
      ]
    end
  end

  describe 'with global reverse lookups' do
    before do
      @do_not_reverse_lookup = BasicSocket.do_not_reverse_lookup
      BasicSocket.do_not_reverse_lookup = false
    end

    after do
      BasicSocket.do_not_reverse_lookup = @do_not_reverse_lookup
    end

    it 'returns an address honoring the global lookup option' do
      addr = Socket.getaddrinfo(nil, 'http', :INET)[0]

      addr[0].should == 'AF_INET'
      addr[1].should == 80

      # We don't have control over this value and there's no way to test this
      # without relying on Socket.getaddrinfo()'s own behaviour (meaning this
      # test would faily any way of the method was not implemented correctly).
      addr[2].should be_an_instance_of(String)
      addr[2].should_not == addr[3]

      addr[3].should == '127.0.0.1'
    end
  end
end
