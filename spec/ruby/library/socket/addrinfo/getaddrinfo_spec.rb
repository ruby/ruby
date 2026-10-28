require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Addrinfo.getaddrinfo' do
  it 'returns an Array of Addrinfo instances' do
    array = Addrinfo.getaddrinfo('127.0.0.1', 80)

    array.should.instance_of?(Array)
    array[0].should.instance_of?(Addrinfo)
  end

  SocketSpecs.each_ip_protocol do |family, ip_address|
    it 'sets the IP address of the Addrinfo instances' do
      array = Addrinfo.getaddrinfo(ip_address, 80)

      array[0].ip_address.should == ip_address
    end

    it 'sets the port of the Addrinfo instances' do
      array = Addrinfo.getaddrinfo(ip_address, 80)

      array[0].ip_port.should == 80
    end

    it 'sets the address family of the Addrinfo instances' do
      array = Addrinfo.getaddrinfo(ip_address, 80)

      array[0].afamily.should == family
    end

    it 'sets the protocol family of the Addrinfo instances' do
      array = Addrinfo.getaddrinfo(ip_address, 80)

      array[0].pfamily.should == family
    end
  end

  guard -> { SocketSpecs.ipv6_available? } do
    it 'sets a custom protocol family of the Addrinfo instances' do
      array = Addrinfo.getaddrinfo('::1', 80, Socket::PF_INET6)

      array[0].pfamily.should == Socket::PF_INET6
    end

    it 'sets a corresponding address family based on a custom protocol family' do
      array = Addrinfo.getaddrinfo('::1', 80, Socket::PF_INET6)

      array[0].afamily.should == Socket::AF_INET6
    end
  end

  platform_is_not :windows do
    it 'sets the default socket type of the Addrinfo instances' do
      array    = Addrinfo.getaddrinfo('127.0.0.1', 80)
      possible = [Socket::SOCK_STREAM, Socket::SOCK_DGRAM]

      possible.should.include?(array[0].socktype)
    end
  end

  it 'sets a custom socket type of the Addrinfo instances' do
    array = Addrinfo.getaddrinfo('127.0.0.1', 80, nil, Socket::SOCK_DGRAM)

    array[0].socktype.should == Socket::SOCK_DGRAM
  end

  platform_is_not :windows do
    it 'sets the default socket protocol of the Addrinfo instances' do
      array    = Addrinfo.getaddrinfo('127.0.0.1', 80)
      possible = [Socket::IPPROTO_TCP, Socket::IPPROTO_UDP]

      possible.should.include?(array[0].protocol)
    end
  end

  it 'sets a custom socket protocol of the Addrinfo instances' do
    array = Addrinfo.getaddrinfo('127.0.0.1', 80, nil, nil, Socket::IPPROTO_UDP)

    array[0].protocol.should == Socket::IPPROTO_UDP
  end

  it 'sets the canonical name when AI_CANONNAME is given as a flag' do
    array = Addrinfo.getaddrinfo('localhost', 80, nil, nil, nil, Socket::AI_CANONNAME)

    array[0].canonname.should.instance_of?(String)
  end
end

describe "Addrinfo.getaddrinfo with a Fiber scheduler" do
  require_relative '../../../core/fiber/fixtures/scheduler'

  before :each do
    @scheduler = Class.new(FiberSpecs::LoggingScheduler) do
      attr_accessor :addresses

      def address_resolve(hostname)
        @events << { event: :address_resolve, fiber: Fiber.current, args: [hostname] }
        @addresses
      end
    end.new
    @scheduler.addresses = ["127.0.0.1"]
    Fiber.set_scheduler(@scheduler)
  end

  after :each do
    Fiber.set_scheduler(nil)
  end

  def getaddrinfo(*args)
    Fiber.new(blocking: false) { Addrinfo.getaddrinfo(*args) }.resume
  end

  it "calls the scheduler's #address_resolve with the host name and uses the addresses it returns" do
    getaddrinfo("example.invalid", 80, :INET, :STREAM).map(&:ip_address).should == ["127.0.0.1"]

    @scheduler.events.map { |e| [e[:event], e[:args]] }.should == [[:address_resolve, ["example.invalid"]]]
  end

  it "only keeps the numeric addresses #address_resolve returns" do
    @scheduler.addresses = ["other.invalid", "127.0.0.2"]

    getaddrinfo("example.invalid", 80, :INET, :STREAM).map(&:ip_address).should == ["127.0.0.2"]
  end

  it "raises SocketError when #address_resolve returns an empty Array, without resolving the host itself" do
    @scheduler.addresses = []

    -> { getaddrinfo("localhost", 80) }.should.raise(SocketError)
    @scheduler.events.map { |e| e[:event] }.should == [:address_resolve]
  end

  it "raises SocketError when #address_resolve returns nil, without resolving the host itself" do
    @scheduler.addresses = nil

    -> { getaddrinfo("localhost", 80) }.should.raise(SocketError)
    @scheduler.events.map { |e| e[:event] }.should == [:address_resolve]
  end

  it "resolves the host itself when the scheduler has no #address_resolve" do
    Fiber.set_scheduler(FiberSpecs::LoggingScheduler.new)

    getaddrinfo("localhost", 80, :INET, :STREAM).map(&:ip_address).should.include?("127.0.0.1")
  end
end
