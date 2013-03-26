#
# Note: Rinda::Ring API is unstable.
#
require 'drb/drb'
require 'rinda/rinda'
require 'thread'
require 'ipaddr'

module Rinda

  ##
  # The default port Ring discovery will use.

  Ring_PORT = 7647

  ##
  # A RingServer allows a Rinda::TupleSpace to be located via UDP broadcasts.
  # Default service location uses the following steps:
  #
  # 1. A RingServer begins listening on the network broadcast UDP address.
  # 2. A RingFinger sends a UDP packet containing the DRb URI where it will
  #    listen for a reply.
  # 3. The RingServer receives the UDP packet and connects back to the
  #    provided DRb URI with the DRb service.
  #
  # A RingServer requires a TupleSpace:
  #
  #   ts = Rinda::TupleSpace.new
  #   rs = Rinda::RingServer.new
  #
  # RingServer can also listen on multicast addresses for announcements.  This
  # allows multiple RingServers to run on the same host.  To use network
  # broadcast and multicast:
  #
  #   ts = Rinda::TupleSpace.new
  #   rs = Rinda::RingServer.new ts, %w[Socket::INADDR_ANY, 239.0.0.1 ff02::1]

  class RingServer

    include DRbUndumped

    ##
    # Special renewer for the RingServer to allow shutdown

    class Renewer # :nodoc:
      include DRbUndumped

      ##
      # Set to false to shutdown future requests using this Renewer

      attr_writer :renew

      def initialize # :nodoc:
        @renew = true
      end

      def renew # :nodoc:
        @renew ? 1 : true
      end
    end

    ##
    # Advertises +ts+ on the given +addresses+ at +port+.
    #
    # If +addresses+ is omitted only the UDP broadcast address is used.
    #
    # +addresses+ can contain multiple addresses.  If a multicast address is
    # given in +addresses+ then the RingServer will listen for multicast
    # queries.

    def initialize(ts, addresses=[Socket::INADDR_ANY], port=Ring_PORT)
      @port = port

      if Integer === addresses then
        addresses, @port = [Socket::INADDR_ANY], addresses
      end

      @renewer = Renewer.new

      @ts = ts
      @sockets = addresses.map do |address|
        make_socket(address)
      end

      @w_services = write_services
      @r_service  = reply_service
    end

    ##
    # Creates a socket at +address+

    def make_socket(address)
      addrinfo = Addrinfo.udp(address, @port)

      socket = Socket.new(addrinfo.pfamily, addrinfo.socktype,
                          addrinfo.protocol)

      if addrinfo.ipv4_multicast? or addrinfo.ipv6_multicast? then
        if Socket.const_defined?(:SO_REUSEPORT) then
          socket.setsockopt(:SOCKET, :SO_REUSEPORT, true)
        else
          socket.setsockopt(:SOCKET, :SO_REUSEADDR, true)
        end

        if addrinfo.ipv4_multicast? then
          mreq = IPAddr.new(addrinfo.ip_address).hton +
            IPAddr.new('0.0.0.0').hton

          socket.setsockopt(:IPPROTO_IP, :IP_ADD_MEMBERSHIP, mreq)
        else
          mreq = IPAddr.new(addrinfo.ip_address).hton + [0].pack('I')

          socket.setsockopt(:IPPROTO_IPV6, :IPV6_JOIN_GROUP, mreq)
        end
      end

      socket.bind(addrinfo)

      socket
    end

    ##
    # Creates threads that pick up UDP packets and passes them to do_write for
    # decoding.

    def write_services
      @sockets.map do |s|
        Thread.new(s) do |socket|
          loop do
            msg = socket.recv(1024)
            do_write(msg)
          end
        end
      end
    end

    ##
    # Extracts the response URI from +msg+ and adds it to TupleSpace where it
    # will be picked up by +reply_service+ for notification.

    def do_write(msg)
      Thread.new do
        begin
          tuple, sec = Marshal.load(msg)
          @ts.write(tuple, sec)
        rescue
        end
      end
    end

    ##
    # Creates a thread that notifies waiting clients from the TupleSpace.

    def reply_service
      Thread.new do
        loop do
          do_reply
        end
      end
    end

    ##
    # Pulls lookup tuples out of the TupleSpace and sends their DRb object the
    # address of the local TupleSpace.

    def do_reply
      tuple = @ts.take([:lookup_ring, DRbObject], @renewer)
      Thread.new { tuple[1].call(@ts) rescue nil}
    rescue
    end

    ##
    # Shuts down the RingServer

    def shutdown
      @renewer.renew = false

      @w_services.each do |thread|
        thread.kill
      end

      @sockets.each do |socket|
        socket.close
      end

      @r_service.kill
    end

  end

  ##
  # RingFinger is used by RingServer clients to discover the RingServer's
  # TupleSpace.  Typically, all a client needs to do is call
  # RingFinger.primary to retrieve the remote TupleSpace, which it can then
  # begin using.
  #
  # To find the first available remote TupleSpace:
  #
  #   Rinda::RingFinger.primary
  #
  # To create a RingFinger that broadcasts to a custom list:
  #
  #   rf = Rinda::RingFinger.new  ['localhost', '192.0.2.1']
  #   rf.primary
  #
  # Rinda::RingFinger also understands multicast addresses and sets them up
  # properly.  This allows you to run multiple RingServers on the same host:
  #
  #   rf = Rinda::RingFinger.new ['239.0.0.1']
  #   rf.primary
  #
  # You can set the hop count (or TTL) for multicast searches using
  # #multicast_hops.
  #
  # If you use IPv6 multicast you may need to set both an address and the
  # outbound interface index:
  #
  #   rf = Rinda::RingFinger.new ['ff02::1']
  #   rf.multicast_interface = 1
  #   rf.primary
  #
  # At this time there is no easy way to get an interface index by name.

  class RingFinger

    @@broadcast_list = ['<broadcast>', 'localhost']

    @@finger = nil

    ##
    # Creates a singleton RingFinger and looks for a RingServer.  Returns the
    # created RingFinger.

    def self.finger
      unless @@finger
        @@finger = self.new
        @@finger.lookup_ring_any
      end
      @@finger
    end

    ##
    # Returns the first advertised TupleSpace.

    def self.primary
      finger.primary
    end

    ##
    # Contains all discovered TupleSpaces except for the primary.

    def self.to_a
      finger.to_a
    end

    ##
    # The list of addresses where RingFinger will send query packets.

    attr_accessor :broadcast_list

    ##
    # Maximum number of hops for sent multicast packets (if using a multicast
    # address in the broadcast list).  The default is 1 (same as UDP
    # broadcast).

    attr_accessor :multicast_hops

    ##
    # The interface index to send IPv6 multicast packets from.

    attr_accessor :multicast_interface

    ##
    # The port that RingFinger will send query packets to.

    attr_accessor :port

    ##
    # Contain the first advertised TupleSpace after lookup_ring_any is called.

    attr_accessor :primary

    ##
    # Creates a new RingFinger that will look for RingServers at +port+ on
    # the addresses in +broadcast_list+.
    #
    # If +broadcast_list+ contains a multicast address then multicast queries
    # will be made using the given multicast_hops and multicast_interface.

    def initialize(broadcast_list=@@broadcast_list, port=Ring_PORT)
      @broadcast_list = broadcast_list || ['localhost']
      @port = port
      @primary = nil
      @rings = []

      @multicast_hops = 1
      @multicast_interface = 0
    end

    ##
    # Contains all discovered TupleSpaces except for the primary.

    def to_a
      @rings
    end

    ##
    # Iterates over all discovered TupleSpaces starting with the primary.

    def each
      lookup_ring_any unless @primary
      return unless @primary
      yield(@primary)
      @rings.each { |x| yield(x) }
    end

    ##
    # Looks up RingServers waiting +timeout+ seconds.  RingServers will be
    # given +block+ as a callback, which will be called with the remote
    # TupleSpace.

    def lookup_ring(timeout=5, &block)
      return lookup_ring_any(timeout) unless block_given?

      msg = Marshal.dump([[:lookup_ring, DRbObject.new(block)], timeout])
      @broadcast_list.each do |it|
        send_message(it, msg)
      end
      sleep(timeout)
    end

    ##
    # Returns the first found remote TupleSpace.  Any further recovered
    # TupleSpaces can be found by calling +to_a+.

    def lookup_ring_any(timeout=5)
      queue = Queue.new

      Thread.new do
        self.lookup_ring(timeout) do |ts|
          queue.push(ts)
        end
        queue.push(nil)
      end

      @primary = queue.pop
      raise('RingNotFound') if @primary.nil?

      Thread.new do
        while it = queue.pop
          @rings.push(it)
        end
      end

      @primary
    end

    ##
    # Creates a socket for +address+ with the appropriate multicast options
    # for multicast addresses.

    def make_socket(address) # :nodoc:
      addrinfo = Addrinfo.udp(address, @port)

      soc = Socket.new(addrinfo.pfamily, addrinfo.socktype, addrinfo.protocol)

      if addrinfo.ipv4_multicast? then
        soc.setsockopt(:IPPROTO_IP, :IP_MULTICAST_LOOP, true)
        soc.setsockopt(:IPPROTO_IP, :IP_MULTICAST_TTL,
                       [@multicast_hops].pack('c'))
      elsif addrinfo.ipv6_multicast? then
        soc.setsockopt(:IPPROTO_IPV6, :IPV6_MULTICAST_LOOP, true)
        soc.setsockopt(:IPPROTO_IPV6, :IPV6_MULTICAST_HOPS,
                       [@multicast_hops].pack('I'))
        soc.setsockopt(:IPPROTO_IPV6, :IPV6_MULTICAST_IF,
                       [@multicast_interface].pack('I'))
      else
        soc.setsockopt(:SOL_SOCKET, :SO_BROADCAST, true)
      end

      soc.connect(addrinfo)

      soc
    end

    def send_message(address, message) # :nodoc:
      soc = make_socket(address)

      soc.send(message, 0)
    rescue
      nil
    ensure
      soc.close if soc
    end

  end

  ##
  # RingProvider uses a RingServer advertised TupleSpace as a name service.
  # TupleSpace clients can register themselves with the remote TupleSpace and
  # look up other provided services via the remote TupleSpace.
  #
  # Services are registered with a tuple of the format [:name, klass,
  # DRbObject, description].

  class RingProvider

    ##
    # Creates a RingProvider that will provide a +klass+ service running on
    # +front+, with a +description+.  +renewer+ is optional.

    def initialize(klass, front, desc, renewer = nil)
      @tuple = [:name, klass, front, desc]
      @renewer = renewer || Rinda::SimpleRenewer.new
    end

    ##
    # Advertises this service on the primary remote TupleSpace.

    def provide
      ts = Rinda::RingFinger.primary
      ts.write(@tuple, @renewer)
    end

  end

end

if __FILE__ == $0
  DRb.start_service
  case ARGV.shift
  when 's'
    require 'rinda/tuplespace'
    ts = Rinda::TupleSpace.new
    Rinda::RingServer.new(ts)
    $stdin.gets
  when 'w'
    finger = Rinda::RingFinger.new(nil)
    finger.lookup_ring do |ts2|
      p ts2
      ts2.write([:hello, :world])
    end
  when 'r'
    finger = Rinda::RingFinger.new(nil)
    finger.lookup_ring do |ts2|
      p ts2
      p ts2.take([nil, nil])
    end
  end
end

