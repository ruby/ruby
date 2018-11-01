require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket.getnameinfo" do
  before :each do
    @reverse_lookup = BasicSocket.do_not_reverse_lookup
    BasicSocket.do_not_reverse_lookup = true
  end

  after :each do
    BasicSocket.do_not_reverse_lookup = @reverse_lookup
  end

  it "gets the name information and don't resolve it" do
    sockaddr = Socket.sockaddr_in 3333, '127.0.0.1'
    name_info = Socket.getnameinfo(sockaddr, Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV)
    name_info.should == ['127.0.0.1', "3333"]
  end

  def should_be_valid_dns_name(name)
    # http://stackoverflow.com/questions/106179/regular-expression-to-match-hostname-or-ip-address
    # ftp://ftp.rfc-editor.org/in-notes/rfc3696.txt
    # http://domainkeys.sourceforge.net/underscore.html
    valid_dns = /^(([a-zA-Z0-9_]|[a-zA-Z0-9_][a-zA-Z0-9\-_]*[a-zA-Z0-9_])\.)*([A-Za-z_]|[A-Za-z_][A-Za-z0-9\-_]*[A-Za-z0-9_])\.?$/
    name.should =~ valid_dns
  end

  it "gets the name information and resolve the host" do
    sockaddr = Socket.sockaddr_in 3333, '127.0.0.1'
    name_info = Socket.getnameinfo(sockaddr, Socket::NI_NUMERICSERV)
    should_be_valid_dns_name(name_info[0])
    name_info[1].should == 3333.to_s
  end

  it "gets the name information and resolves the service" do
    sockaddr = Socket.sockaddr_in 9, '127.0.0.1'
    name_info = Socket.getnameinfo(sockaddr)
    name_info.size.should == 2
    should_be_valid_dns_name(name_info[0])
    # see http://www.iana.org/assignments/port-numbers
    name_info[1].should == 'discard'
  end

  it "gets a 3-element array and doesn't resolve hostname" do
    name_info = Socket.getnameinfo(["AF_INET", 3333, '127.0.0.1'], Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV)
    name_info.should == ['127.0.0.1', "3333"]
  end

  it "gets a 3-element array and resolves the service" do
    name_info = Socket.getnameinfo ["AF_INET", 9, '127.0.0.1']
    name_info[1].should == 'discard'
  end

  it "gets a 4-element array and doesn't resolve hostname" do
    name_info = Socket.getnameinfo(["AF_INET", 3333, 'foo', '127.0.0.1'], Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV)
    name_info.should == ['127.0.0.1', "3333"]
  end

  it "gets a 4-element array and resolves the service" do
    name_info = Socket.getnameinfo ["AF_INET", 9, 'foo', '127.0.0.1']
    name_info[1].should == 'discard'
  end
end

describe 'Socket.getnameinfo' do
  describe 'using a String as the first argument' do
    before do
      @addr = Socket.sockaddr_in(21, '127.0.0.1')
    end

    it 'raises SocketError or TypeError when using an invalid String' do
      lambda { Socket.getnameinfo('cats') }.should raise_error(Exception) { |e|
        [SocketError, TypeError].should include(e.class)
      }
    end

    describe 'without custom flags' do
      it 'returns an Array containing the hostname and service name' do
        Socket.getnameinfo(@addr).should == [SocketSpecs.hostname_reverse_lookup, 'ftp']
      end
    end

    describe 'using NI_NUMERICHOST as the flag' do
      it 'returns an Array containing the numeric hostname and service name' do
        array = Socket.getnameinfo(@addr, Socket::NI_NUMERICHOST)

        %w{127.0.0.1 ::1}.include?(array[0]).should == true

        array[1].should == 'ftp'
      end
    end
  end

  SocketSpecs.each_ip_protocol do |family, ip_address, family_name|
    before do
      @hostname = SocketSpecs.hostname_reverse_lookup(ip_address)
    end

    describe 'using a 3 element Array as the first argument' do
      before do
        @addr = [family_name, 21, @hostname]
      end

      it 'raises ArgumentError when using an invalid Array' do
        lambda { Socket.getnameinfo([family_name]) }.should raise_error(ArgumentError)
      end

      platform_is_not :windows do
        describe 'using NI_NUMERICHOST as the flag' do
          it 'returns an Array containing the numeric hostname and service name' do
            Socket.getnameinfo(@addr, Socket::NI_NUMERICHOST).should == [ip_address, 'ftp']
          end
        end
      end
    end

    describe 'using a 4 element Array as the first argument' do
      before do
        @addr = [family_name, 21, ip_address, ip_address]
      end

      describe 'without custom flags' do
        it 'returns an Array containing the hostname and service name' do
          array = Socket.getnameinfo(@addr)
          array.should be_an_instance_of(Array)
          array[0].should == @hostname
          array[1].should == 'ftp'
        end

        it 'uses the 3rd value as the hostname if the 4th is not present' do
          addr = [family_name, 21, ip_address, nil]

          array = Socket.getnameinfo(addr)
          array.should be_an_instance_of(Array)
          array[0].should == @hostname
          array[1].should == 'ftp'
        end
      end

      describe 'using NI_NUMERICHOST as the flag' do
        it 'returns an Array containing the numeric hostname and service name' do
          Socket.getnameinfo(@addr, Socket::NI_NUMERICHOST).should == [ip_address, 'ftp']
        end
      end
    end
  end
end
