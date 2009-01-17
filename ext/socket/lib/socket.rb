require 'socket.so'

class AddrInfo
  # creates an AddrInfo object from the arguments.
  #
  # The arguments are interpreted as similar to self.
  #
  #   AddrInfo.tcp("0.0.0.0", 4649).family_addrinfo("www.ruby-lang.org", 80)
  #   #=> #<AddrInfo: 221.186.184.68:80 TCP (www.ruby-lang.org:80)>
  #
  #   AddrInfo.unix("/tmp/sock").family_addrinfo("/tmp/sock2")
  #   #=> #<AddrInfo: /tmp/sock2 SOCK_STREAM>
  #
  def family_addrinfo(*args)
    if args.empty?
      raise ArgumentError, "no address specified"
    elsif AddrInfo === args.first
      raise ArgumentError, "too man argument" if args.length != 1
    elsif self.ip?
      raise ArgumentError, "IP address needs host and port but #{args.length} arguments given" if args.length != 2
      host, port = args
      AddrInfo.getaddrinfo(host, port, self.pfamily, self.socktype, self.protocol)[0]
    elsif self.unix?
      raise ArgumentError, "UNIX socket needs single path argument but #{args.length} arguments given" if args.length != 1
      path, = args
      AddrInfo.unix(path)
    else
      raise ArgumentError, "unexpected family"
    end
  end

  def connect_internal(local_addrinfo)
    sock = Socket.new(self.pfamily, self.socktype, self.protocol)
    begin
      sock.ipv6only! if self.ipv6?
      sock.bind local_addrinfo if local_addrinfo
      sock.connect(self)
      if block_given?
        yield sock
      else
        sock
      end
    ensure
      sock.close if !sock.closed? && (block_given? || $!)
    end
  end
  private :connect_internal

  # creates a socket connected to self.
  #
  # If one or more arguments given as _local_addr_args_,
  # it is used as the local address of the socket.
  # _local_addr_args_ is given for family_addrinfo to obtain actual address.
  #
  # If no arguments given, the local address of the socket is not bound.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   AddrInfo.tcp("www.ruby-lang.org", 80).connect_from("0.0.0.0", 4649) {|s|
  #     s.print "GET / HTTP/1.0\r\n\r\n"
  #     p s.read
  #   }
  #
  #   # AddrInfo object can be taken for the argument.
  #   AddrInfo.tcp("www.ruby-lang.org", 80).connect_from(AddrInfo.tcp("0.0.0.0", 4649)) {|s|
  #     s.print "GET / HTTP/1.0\r\n\r\n"
  #     p s.read
  #   }
  #
  def connect_from(*local_addr_args, &block)
    connect_internal(family_addrinfo(*local_addr_args), &block)
  end

  # creates a socket connected to self.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   AddrInfo.tcp("www.ruby-lang.org", 80).connect {|s|
  #     s.print "GET / HTTP/1.0\r\n\r\n"
  #     p s.read
  #   }
  #
  def connect(&block)
    connect_internal(nil, &block)
  end

  # creates a socket connected to _remote_addr_args_ and bound to self.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   AddrInfo.tcp("0.0.0.0", 4649).connect_to("www.ruby-lang.org", 80) {|s|
  #     s.print "GET / HTTP/1.0\r\n\r\n"
  #     p s.read
  #   }
  #
  def connect_to(*remote_addr_args, &block)
    remote_addrinfo = family_addrinfo(*remote_addr_args)
    remote_addrinfo.send(:connect_internal, self, &block)
  end

  # creates a socket bound to self.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   AddrInfo.udp("0.0.0.0", 9981).bind {|s|
  #     s.local_address.connect {|s| s.send "hello", 0 }
  #     p s.recv(10) #=> "hello"
  #   }
  #
  def bind
    sock = Socket.new(self.pfamily, self.socktype, self.protocol)
    begin
      sock.ipv6only! if self.ipv6?
      sock.setsockopt(:SOCKET, :REUSEADDR, 1)
      sock.bind(self)
      if block_given?
        yield sock
      else
        sock
      end
    ensure
      sock.close if !sock.closed? && (block_given? || $!)
    end
  end

  # creates a listening socket bound to self.
  def listen(backlog=5)
    sock = Socket.new(self.pfamily, self.socktype, self.protocol)
    begin
      sock.ipv6only! if self.ipv6?
      sock.setsockopt(:SOCKET, :REUSEADDR, 1)
      sock.bind(self)
      sock.listen(backlog)
      if block_given?
        yield sock
      else
        sock
      end
    ensure
      sock.close if !sock.closed? && (block_given? || $!)
    end
  end

  # iterates over the list of AddrInfo objects obtained by AddrInfo.getaddrinfo.
  #
  #   AddrInfo.foreach(nil, 80) {|x| p x }
  #   #=> #<AddrInfo: 127.0.0.1:80 TCP (:80)>
  #   #   #<AddrInfo: 127.0.0.1:80 UDP (:80)>
  #   #   #<AddrInfo: [::1]:80 TCP (:80)>
  #   #   #<AddrInfo: [::1]:80 UDP (:80)>
  #
  def self.foreach(nodename, service, family=nil, socktype=nil, protocol=nil, flags=nil, &block)
    AddrInfo.getaddrinfo(nodename, service, family, socktype, protocol, flags).each(&block)
  end
end

class Socket
  # enable the socket option IPV6_V6ONLY if IPV6_V6ONLY is available.
  def ipv6only!
    if Socket.const_defined?(:IPV6_V6ONLY)
      self.setsockopt(:IPV6, :V6ONLY, 1)
    end
  end

  # creates a new socket object connected to host:port using TCP.
  #
  # If local_host:local_port is given,
  # the socket is bound to it.
  #
  # If a block is given, the block is called with the socket.
  # The value of the block is returned.
  # The socket is closed when this method returns.
  #
  # If no block is given, the socket is returned.
  #
  #   Socket.tcp("www.ruby-lang.org", 80) {|sock|
  #     sock.print "GET / HTTP/1.0\r\n\r\n"
  #     sock.close_write
  #     print sock.read
  #   }
  #
  def self.tcp(host, port, local_host=nil, local_port=nil) # :yield: socket
    last_error = nil
    ret = nil

    local_addr_list = nil
    if local_host != nil || local_port != nil
      local_addr_list = AddrInfo.getaddrinfo(local_host, local_port, nil, :STREAM, nil)
    end

    AddrInfo.foreach(host, port, nil, :STREAM) {|ai|
      if local_addr_list
        local_addr = local_addr_list.find {|local_ai| local_ai.afamily == ai.afamily }
        next if !local_addr
      else
        local_addr = nil
      end
      begin
        sock = local_addr ? ai.connect_from(local_addr) : ai.connect
      rescue SystemCallError
        last_error = $!
        next
      end
      ret = sock
      break
    }
    if !ret
      if last_error
        raise last_error
      else
        raise SocketError, "no appropriate local address"
      end
    end
    if block_given?
      begin
        yield ret
      ensure
        ret.close if !ret.closed?
      end
    else
      ret
    end
  end

  # creates a TCP server on _port_ and calls the block for each connection accepted.
  # The block is called with a socket and a client_address as an AddrInfo object.
  #
  # If _host_ is specified, it is used with _port_ to determine the server addresses.
  #
  # The socket is *not* closed when the block returns.
  # So application should close it explicitly.
  #
  # This method calls the block sequentially.
  # It means that the next connection is not accepted until the block returns.
  # So concurrent mechanism, thread for example, should be used to service multiple clients at a time.
  #
  # Note that AddrInfo.getaddrinfo is used to determine the server socket addresses.
  # When AddrInfo.getaddrinfo returns two or more addresses,
  # IPv4 and IPv6 address for example,
  # all of them are used.
  # Socket.tcp_server_loop succeeds if one socket can be used at least.
  #
  #   # Sequential echo server.
  #   # It services only one client at a time.
  #   Socket.tcp_server_loop(16807) {|sock, client_addrinfo|
  #     begin
  #       IO.copy_stream(sock, sock)
  #     ensure
  #       sock.close
  #     end
  #   }
  #
  #   # Threaded echo server
  #   # It services multiple clients at a time.
  #   # Note that it may accept connections too much.
  #   Socket.tcp_server_loop(16807) {|sock, client_addrinfo|
  #     Thread.new {
  #       begin
  #         IO.copy_stream(sock, sock)
  #       ensure
  #         sock.close
  #       end
  #     }
  #   }
  #
  def self.tcp_server_loop(host=nil, port) # :yield: socket, client_addrinfo
    last_error = nil
    sockets = []
    AddrInfo.foreach(host, port, nil, :STREAM, nil, Socket::AI_PASSIVE) {|ai|
      begin
        s = ai.listen
      rescue SystemCallError
        last_error = $!
        next
      end
      sockets << s
    }
    if sockets.empty?
      raise last_error
    end
    loop {
      readable, _, _ = IO.select(sockets)
      readable.each {|r|
        begin
          sock, addr = r.accept_nonblock
        rescue Errno::EWOULDBLOCK
          next
        end
        yield sock, addr
      }
    }
  ensure
    sockets.each {|s|
      s.close if !s.closed?
    }
  end

  # creates a new socket connected to path using UNIX socket socket.
  #
  # If a block is given, the block is called with the socket.
  # The value of the block is returned.
  # The socket is closed when this method returns.
  #
  # If no block is given, the socket is returned.
  #
  #   # talk to /tmp/sock socket.
  #   Socket.unix("/tmp/sock") {|sock|
  #     t = Thread.new { IO.copy_stream(sock, STDOUT) }
  #     IO.copy_stream(STDIN, sock)
  #     t.join
  #   }
  #
  def self.unix(path) # :yield: socket
    addr = AddrInfo.unix(path)
    sock = addr.connect
    if block_given?
      begin
        yield sock
      ensure
        sock.close if !sock.closed?
      end
    else
      sock
    end
  end

  # creates a UNIX socket server on _path_.
  # It calls the block for each socket accepted.
  #
  # If _host_ is specified, it is used with _port_ to determine the server ports.
  #
  # The socket is *not* closed when the block returns.
  # So application should close it.
  #
  # This method deletes the socket file pointed by _path_ at first if
  # the file is a socket file and it is owned by the user of the application.
  # This is safe only if the directory of _path_ is not changed by a malicious user.
  # So don't use /tmp/malicious-users-directory/socket.
  # Note that /tmp/socket and /tmp/your-private-directory/socket is safe assuming that /tmp has sticky bit.
  #
  #   # Sequential echo server.
  #   # It services only one client at a time.
  #   Socket.unix_server_loop("/tmp/sock") {|sock, client_addrinfo|
  #     begin
  #       IO.copy_stream(sock, sock)
  #     ensure
  #       sock.close
  #     end
  #   }
  #
  def self.unix_server_loop(path) # :yield: socket, client_addrinfo
    begin
      st = File.lstat(path)
    rescue Errno::ENOENT
    end
    if st && st.socket? && st.owned?
      File.unlink path
    end
    serv = AddrInfo.unix(path).listen
    loop {
      sock, addr = serv.accept
      yield sock, addr
    }
  ensure
    serv.close if serv && !serv.closed?
  end

end

