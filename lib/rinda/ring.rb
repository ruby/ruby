#
# Note: Rinda::Ring API is unstable.
#
require 'drb/drb'
require 'rinda/rinda'
require 'thread'

module Rinda
  Ring_PORT = 7647
  class RingServer
    include DRbUndumped

    def initialize(ts, port=Ring_PORT)
      @ts = ts
      @soc = UDPSocket.open
      @soc.bind('', port)
      @w_service = write_service
      @r_service = reply_service
    end

    def write_service
      Thread.new do
	loop do
	  msg, addr = @soc.recvfrom(1024)
	  do_write(msg)
	end
      end
    end
  
    def do_write(msg)
      Thread.new do
	begin
	  tuple, sec = Marshal.load(msg)
	  @ts.write(tuple, sec)
	rescue
	end
      end
    end

    def reply_service
      Thread.new do
	loop do
	  do_reply
	end
      end
    end
    
    def do_reply
      tuple = @ts.take([:lookup_ring, DRbObject])
      Thread.new { tuple[1].call(@ts) rescue nil}
    rescue
    end
  end

  class RingFinger
    @@finger = nil
    def self.finger
      unless @@finger 
	@@finger = self.new
	@@finger.lookup_ring_any
      end
      @@finger
    end

    def self.primary
      finger.primary
    end

    def self.to_a
      finger.to_a
    end

    @@broadcast_list = ['<broadcast>', 'localhost']
    def initialize(broadcast_list=@@broadcast_list, port=Ring_PORT)
      @broadcast_list = broadcast_list || ['localhost']
      @port = port
      @primary = nil
      @rings = []
    end
    attr_accessor :broadcast_list, :port, :primary

    def to_a
      @rings
    end

    def each
      lookup_ring_any unless @primary
      return unless @primary
      yield(@primary)
      @rings.each { |x| yield(x) }
    end

    def lookup_ring(timeout=5, &block)
      return lookup_ring_any(timeout) unless block_given?

      msg = Marshal.dump([[:lookup_ring, DRbObject.new(block)], timeout])
      @broadcast_list.each do |it|
	soc = UDPSocket.open
	begin
	  soc.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
	  soc.send(msg, 0, it, @port)
	rescue
	  nil
	ensure
	  soc.close
	end
      end
      sleep(timeout)
    end

    def lookup_ring_any(timeout=5)
      queue = Queue.new

      th = Thread.new do
	self.lookup_ring(timeout) do |ts|
	  queue.push(ts)
	end
	queue.push(nil)
	while it = queue.pop
	  @rings.push(it)
	end
      end
      
      @primary = queue.pop
      raise('RingNotFound') if @primary.nil?
      @primary
    end
  end

  class RingProvider
    def initialize(klass, front, desc, renewer = nil)
      @tuple = [:name, klass, front, desc]
      @renewer = renewer || Rinda::SimpleRenewer.new
    end

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
    place = Rinda::RingServer.new(ts)
    $stdin.gets
  when 'w'
    finger = Rinda::RingFinger.new(nil)
    finger.lookup_ring do |ts|
      p ts
      ts.write([:hello, :world])
    end
  when 'r'
    finger = Rinda::RingFinger.new(nil)
    finger.lookup_ring do |ts|
      p ts
      p ts.take([nil, nil])
    end
  end
end
