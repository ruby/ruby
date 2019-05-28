require 'socket'

module SocketSpecs
  # helper to get the hostname associated to 127.0.0.1 or the given ip
  def self.hostname(ip = "127.0.0.1")
    # Calculate each time, without caching, since the result might
    # depend on things like do_not_reverse_lookup mode, which is
    # changing from test to test
    Socket.getaddrinfo(ip, nil)[0][2]
  end

  def self.hostname_reverse_lookup(ip = "127.0.0.1")
    Socket.getaddrinfo(ip, nil, 0, 0, 0, 0, true)[0][2]
  end

  def self.addr(which=:ipv4)
    case which
    when :ipv4
      host = "127.0.0.1"
    when :ipv6
      host = "::1"
    end
    Socket.getaddrinfo(host, nil)[0][3]
  end

  def self.reserved_unused_port
    # https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
    0
  end

  def self.sockaddr_in(port, host)
    Socket::SockAddr_In.new(Socket.sockaddr_in(port, host))
  end

  def self.socket_path
    path = tmp("unix.sock", false)
    # Check for too long unix socket path (max 108 bytes including \0 => 107)
    # Note that Linux accepts not null-terminated paths but the man page advises against it.
    if path.bytesize > 107
      path = "/tmp/unix_server_spec.socket"
    end
    rm_socket(path)
    path
  end

  def self.rm_socket(path)
    File.delete(path) if File.exist?(path)
  end

  def self.ipv6_available?
    @ipv6_available ||= begin
      server = TCPServer.new('::1', 0)
    rescue Errno::EAFNOSUPPORT, Errno::EADDRNOTAVAIL, SocketError
      :no
    else
      server.close
      :yes
    end
    @ipv6_available == :yes
  end

  def self.each_ip_protocol
    describe 'using IPv4' do
      yield Socket::AF_INET, '127.0.0.1', 'AF_INET'
    end

    guard -> { SocketSpecs.ipv6_available? } do
      describe 'using IPv6' do
        yield Socket::AF_INET6, '::1', 'AF_INET6'
      end
    end
  end

  def self.loop_with_timeout(timeout = TIME_TOLERANCE)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    while yield == :retry
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) - start >= timeout
        raise RuntimeError, "Did not succeed within #{timeout} seconds"
      end
    end
  end

  def self.dest_addr_req_error
    error = Errno::EDESTADDRREQ
    platform_is :windows do
      error = Errno::ENOTCONN
    end
    error
  end

  # TCPServer echo server accepting one connection
  class SpecTCPServer
    attr_reader :hostname, :port

    def initialize
      @hostname = SocketSpecs.hostname
      @server = TCPServer.new @hostname, 0
      @port = @server.addr[1]

      log "SpecTCPServer starting on #{@hostname}:#{@port}"

      @thread = Thread.new do
        socket = @server.accept
        log "SpecTCPServer accepted connection: #{socket}"
        service socket
      end
    end

    def service(socket)
      begin
        data = socket.recv(1024)

        return if data.empty?
        log "SpecTCPServer received: #{data.inspect}"

        return if data == "QUIT"

        socket.send data, 0
      ensure
        socket.close
      end
    end

    def shutdown
      log "SpecTCPServer shutting down"
      @thread.join
      @server.close
    end

    def log(message)
      @logger.puts message if @logger
    end
  end
end
