# frozen_string_literal: true

require 'socket.so'

unless IO.method_defined?(:wait_writable, false)
  # It's only required on older Rubies < v3.2:
  require 'io/wait'
end

class Addrinfo
  # creates an Addrinfo object from the arguments.
  #
  # The arguments are interpreted as similar to self.
  #
  #   Addrinfo.tcp("0.0.0.0", 4649).family_addrinfo("www.ruby-lang.org", 80)
  #   #=> #<Addrinfo: 221.186.184.68:80 TCP (www.ruby-lang.org:80)>
  #
  #   Addrinfo.unix("/tmp/sock").family_addrinfo("/tmp/sock2")
  #   #=> #<Addrinfo: /tmp/sock2 SOCK_STREAM>
  #
  def family_addrinfo(*args)
    if args.empty?
      raise ArgumentError, "no address specified"
    elsif Addrinfo === args.first
      raise ArgumentError, "too many arguments" if args.length != 1
      addrinfo = args.first
      if (self.pfamily != addrinfo.pfamily) ||
         (self.socktype != addrinfo.socktype)
        raise ArgumentError, "Addrinfo type mismatch"
      end
      addrinfo
    elsif self.ip?
      raise ArgumentError, "IP address needs host and port but #{args.length} arguments given" if args.length != 2
      host, port = args
      Addrinfo.getaddrinfo(host, port, self.pfamily, self.socktype, self.protocol)[0]
    elsif self.unix?
      raise ArgumentError, "UNIX socket needs single path argument but #{args.length} arguments given" if args.length != 1
      path, = args
      Addrinfo.unix(path)
    else
      raise ArgumentError, "unexpected family"
    end
  end

  # creates a new Socket connected to the address of +local_addrinfo+.
  #
  # If _local_addrinfo_ is nil, the address of the socket is not bound.
  #
  # The _timeout_ specify the seconds for timeout.
  # Errno::ETIMEDOUT is raised when timeout occur.
  #
  # If a block is given the created socket is yielded for each address.
  #
  def connect_internal(local_addrinfo, timeout=nil) # :yields: socket
    sock = Socket.new(self.pfamily, self.socktype, self.protocol)
    begin
      sock.ipv6only! if self.ipv6?
      sock.bind local_addrinfo if local_addrinfo
      if timeout
        case sock.connect_nonblock(self, exception: false)
        when 0 # success or EISCONN, other errors raise
          break
        when :wait_writable
          sock.wait_writable(timeout) or
            raise Errno::ETIMEDOUT, 'user specified timeout'
        end while true
      else
        sock.connect(self)
      end
    rescue Exception
      sock.close
      raise
    end
    if block_given?
      begin
        yield sock
      ensure
        sock.close
      end
    else
      sock
    end
  end
  protected :connect_internal

  # :call-seq:
  #   addrinfo.connect_from([local_addr_args], [opts]) {|socket| ... }
  #   addrinfo.connect_from([local_addr_args], [opts])
  #
  # creates a socket connected to the address of self.
  #
  # If one or more arguments given as _local_addr_args_,
  # it is used as the local address of the socket.
  # _local_addr_args_ is given for family_addrinfo to obtain actual address.
  #
  # If _local_addr_args_ is not given, the local address of the socket is not bound.
  #
  # The optional last argument _opts_ is options represented by a hash.
  # _opts_ may have following options:
  #
  # [:timeout] specify the timeout in seconds.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   Addrinfo.tcp("www.ruby-lang.org", 80).connect_from("0.0.0.0", 4649) {|s|
  #     s.print "GET / HTTP/1.0\r\nHost: www.ruby-lang.org\r\n\r\n"
  #     puts s.read
  #   }
  #
  #   # Addrinfo object can be taken for the argument.
  #   Addrinfo.tcp("www.ruby-lang.org", 80).connect_from(Addrinfo.tcp("0.0.0.0", 4649)) {|s|
  #     s.print "GET / HTTP/1.0\r\nHost: www.ruby-lang.org\r\n\r\n"
  #     puts s.read
  #   }
  #
  def connect_from(*args, timeout: nil, &block)
    connect_internal(family_addrinfo(*args), timeout, &block)
  end

  # :call-seq:
  #   addrinfo.connect([opts]) {|socket| ... }
  #   addrinfo.connect([opts])
  #
  # creates a socket connected to the address of self.
  #
  # The optional argument _opts_ is options represented by a hash.
  # _opts_ may have following options:
  #
  # [:timeout] specify the timeout in seconds.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   Addrinfo.tcp("www.ruby-lang.org", 80).connect {|s|
  #     s.print "GET / HTTP/1.0\r\nHost: www.ruby-lang.org\r\n\r\n"
  #     puts s.read
  #   }
  #
  def connect(timeout: nil, &block)
    connect_internal(nil, timeout, &block)
  end

  # :call-seq:
  #   addrinfo.connect_to([remote_addr_args], [opts]) {|socket| ... }
  #   addrinfo.connect_to([remote_addr_args], [opts])
  #
  # creates a socket connected to _remote_addr_args_ and bound to self.
  #
  # The optional last argument _opts_ is options represented by a hash.
  # _opts_ may have following options:
  #
  # [:timeout] specify the timeout in seconds.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   Addrinfo.tcp("0.0.0.0", 4649).connect_to("www.ruby-lang.org", 80) {|s|
  #     s.print "GET / HTTP/1.0\r\nHost: www.ruby-lang.org\r\n\r\n"
  #     puts s.read
  #   }
  #
  def connect_to(*args, timeout: nil, &block)
    remote_addrinfo = family_addrinfo(*args)
    remote_addrinfo.connect_internal(self, timeout, &block)
  end

  # creates a socket bound to self.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   Addrinfo.udp("0.0.0.0", 9981).bind {|s|
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
    rescue Exception
      sock.close
      raise
    end
    if block_given?
      begin
        yield sock
      ensure
        sock.close
      end
    else
      sock
    end
  end

  # creates a listening socket bound to self.
  def listen(backlog=Socket::SOMAXCONN)
    sock = Socket.new(self.pfamily, self.socktype, self.protocol)
    begin
      sock.ipv6only! if self.ipv6?
      sock.setsockopt(:SOCKET, :REUSEADDR, 1) unless self.pfamily == Socket::PF_UNIX
      sock.bind(self)
      sock.listen(backlog)
    rescue Exception
      sock.close
      raise
    end
    if block_given?
      begin
        yield sock
      ensure
        sock.close
      end
    else
      sock
    end
  end

  # iterates over the list of Addrinfo objects obtained by Addrinfo.getaddrinfo.
  #
  #   Addrinfo.foreach(nil, 80) {|x| p x }
  #   #=> #<Addrinfo: 127.0.0.1:80 TCP (:80)>
  #   #   #<Addrinfo: 127.0.0.1:80 UDP (:80)>
  #   #   #<Addrinfo: [::1]:80 TCP (:80)>
  #   #   #<Addrinfo: [::1]:80 UDP (:80)>
  #
  def self.foreach(nodename, service, family=nil, socktype=nil, protocol=nil, flags=nil, timeout: nil, &block)
    Addrinfo.getaddrinfo(nodename, service, family, socktype, protocol, flags, timeout: timeout).each(&block)
  end
end

class BasicSocket < IO
  # Returns an address of the socket suitable for connect in the local machine.
  #
  # This method returns _self_.local_address, except following condition.
  #
  # - IPv4 unspecified address (0.0.0.0) is replaced by IPv4 loopback address (127.0.0.1).
  # - IPv6 unspecified address (::) is replaced by IPv6 loopback address (::1).
  #
  # If the local address is not suitable for connect, SocketError is raised.
  # IPv4 and IPv6 address which port is 0 is not suitable for connect.
  # Unix domain socket which has no path is not suitable for connect.
  #
  #   Addrinfo.tcp("0.0.0.0", 0).listen {|serv|
  #     p serv.connect_address #=> #<Addrinfo: 127.0.0.1:53660 TCP>
  #     serv.connect_address.connect {|c|
  #       s, _ = serv.accept
  #       p [c, s] #=> [#<Socket:fd 4>, #<Socket:fd 6>]
  #     }
  #   }
  #
  def connect_address
    addr = local_address
    afamily = addr.afamily
    if afamily == Socket::AF_INET
      raise SocketError, "unbound IPv4 socket" if addr.ip_port == 0
      if addr.ip_address == "0.0.0.0"
        addr = Addrinfo.new(["AF_INET", addr.ip_port, nil, "127.0.0.1"], addr.pfamily, addr.socktype, addr.protocol)
      end
    elsif defined?(Socket::AF_INET6) && afamily == Socket::AF_INET6
      raise SocketError, "unbound IPv6 socket" if addr.ip_port == 0
      if addr.ip_address == "::"
        addr = Addrinfo.new(["AF_INET6", addr.ip_port, nil, "::1"], addr.pfamily, addr.socktype, addr.protocol)
      elsif addr.ip_address == "0.0.0.0" # MacOS X 10.4 returns "a.b.c.d" for IPv4-mapped IPv6 address.
        addr = Addrinfo.new(["AF_INET6", addr.ip_port, nil, "::1"], addr.pfamily, addr.socktype, addr.protocol)
      elsif addr.ip_address == "::ffff:0.0.0.0" # MacOS X 10.6 returns "::ffff:a.b.c.d" for IPv4-mapped IPv6 address.
        addr = Addrinfo.new(["AF_INET6", addr.ip_port, nil, "::1"], addr.pfamily, addr.socktype, addr.protocol)
      end
    elsif defined?(Socket::AF_UNIX) && afamily == Socket::AF_UNIX
      raise SocketError, "unbound Unix socket" if addr.unix_path == ""
    end
    addr
  end

  # call-seq:
  #    basicsocket.sendmsg(mesg, flags=0, dest_sockaddr=nil, *controls) => numbytes_sent
  #
  # sendmsg sends a message using sendmsg(2) system call in blocking manner.
  #
  # _mesg_ is a string to send.
  #
  # _flags_ is bitwise OR of MSG_* constants such as Socket::MSG_OOB.
  #
  # _dest_sockaddr_ is a destination socket address for connection-less socket.
  # It should be a sockaddr such as a result of Socket.sockaddr_in.
  # An Addrinfo object can be used too.
  #
  # _controls_ is a list of ancillary data.
  # The element of _controls_ should be Socket::AncillaryData or
  # 3-elements array.
  # The 3-element array should contains cmsg_level, cmsg_type and data.
  #
  # The return value, _numbytes_sent_ is an integer which is the number of bytes sent.
  #
  # sendmsg can be used to implement send_io as follows:
  #
  #   # use Socket::AncillaryData.
  #   ancdata = Socket::AncillaryData.int(:UNIX, :SOCKET, :RIGHTS, io.fileno)
  #   sock.sendmsg("a", 0, nil, ancdata)
  #
  #   # use 3-element array.
  #   ancdata = [:SOCKET, :RIGHTS, [io.fileno].pack("i!")]
  #   sock.sendmsg("\0", 0, nil, ancdata)
  def sendmsg(mesg, flags = 0, dest_sockaddr = nil, *controls)
    __sendmsg(mesg, flags, dest_sockaddr, controls)
  end

  # call-seq:
  #    basicsocket.sendmsg_nonblock(mesg, flags=0, dest_sockaddr=nil, *controls, opts={}) => numbytes_sent
  #
  # sendmsg_nonblock sends a message using sendmsg(2) system call in non-blocking manner.
  #
  # It is similar to BasicSocket#sendmsg
  # but the non-blocking flag is set before the system call
  # and it doesn't retry the system call.
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that sendmsg_nonblock should not raise an IO::WaitWritable exception, but
  # return the symbol +:wait_writable+ instead.
  def sendmsg_nonblock(mesg, flags = 0, dest_sockaddr = nil, *controls,
                       exception: true)
    __sendmsg_nonblock(mesg, flags, dest_sockaddr, controls, exception)
  end

  # call-seq:
  # 	basicsocket.recv_nonblock(maxlen [, flags [, buf [, options ]]]) => mesg
  #
  # Receives up to _maxlen_ bytes from +socket+ using recvfrom(2) after
  # O_NONBLOCK is set for the underlying file descriptor.
  # _flags_ is zero or more of the +MSG_+ options.
  # The result, _mesg_, is the data received.
  #
  # When recvfrom(2) returns 0, Socket#recv_nonblock returns nil.
  # In most cases it means the connection was closed, but for UDP connections
  # it may mean an empty packet was received, as the underlying API makes
  # it impossible to distinguish these two cases.
  #
  # === Parameters
  # * +maxlen+ - the number of bytes to receive from the socket
  # * +flags+ - zero or more of the +MSG_+ options
  # * +buf+ - destination String buffer
  # * +options+ - keyword hash, supporting `exception: false`
  #
  # === Example
  # 	serv = TCPServer.new("127.0.0.1", 0)
  # 	af, port, host, addr = serv.addr
  # 	c = TCPSocket.new(addr, port)
  # 	s = serv.accept
  # 	c.send "aaa", 0
  # 	begin # emulate blocking recv.
  # 	  p s.recv_nonblock(10) #=> "aaa"
  # 	rescue IO::WaitReadable
  # 	  IO.select([s])
  # 	  retry
  # 	end
  #
  # Refer to Socket#recvfrom for the exceptions that may be thrown if the call
  # to _recv_nonblock_ fails.
  #
  # BasicSocket#recv_nonblock may raise any error corresponding to recvfrom(2) failure,
  # including Errno::EWOULDBLOCK.
  #
  # If the exception is Errno::EWOULDBLOCK or Errno::EAGAIN,
  # it is extended by IO::WaitReadable.
  # So IO::WaitReadable can be used to rescue the exceptions for retrying recv_nonblock.
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that recv_nonblock should not raise an IO::WaitReadable exception, but
  # return the symbol +:wait_readable+ instead.
  #
  # === See
  # * Socket#recvfrom
  def recv_nonblock(len, flag = 0, str = nil, exception: true)
    __recv_nonblock(len, flag, str, exception)
  end

  # call-seq:
  #    basicsocket.recvmsg(maxmesglen=nil, flags=0, maxcontrollen=nil, opts={}) => [mesg, sender_addrinfo, rflags, *controls]
  #
  # recvmsg receives a message using recvmsg(2) system call in blocking manner.
  #
  # _maxmesglen_ is the maximum length of mesg to receive.
  #
  # _flags_ is bitwise OR of MSG_* constants such as Socket::MSG_PEEK.
  #
  # _maxcontrollen_ is the maximum length of controls (ancillary data) to receive.
  #
  # _opts_ is option hash.
  # Currently :scm_rights=>bool is the only option.
  #
  # :scm_rights option specifies that application expects SCM_RIGHTS control message.
  # If the value is nil or false, application don't expects SCM_RIGHTS control message.
  # In this case, recvmsg closes the passed file descriptors immediately.
  # This is the default behavior.
  #
  # If :scm_rights value is neither nil nor false, application expects SCM_RIGHTS control message.
  # In this case, recvmsg creates IO objects for each file descriptors for
  # Socket::AncillaryData#unix_rights method.
  #
  # The return value is 4-elements array.
  #
  # _mesg_ is a string of the received message.
  #
  # _sender_addrinfo_ is a sender socket address for connection-less socket.
  # It is an Addrinfo object.
  # For connection-oriented socket such as TCP, sender_addrinfo is platform dependent.
  #
  # _rflags_ is a flags on the received message which is bitwise OR of MSG_* constants such as Socket::MSG_TRUNC.
  # It will be nil if the system uses 4.3BSD style old recvmsg system call.
  #
  # _controls_ is ancillary data which is an array of Socket::AncillaryData objects such as:
  #
  #   #<Socket::AncillaryData: AF_UNIX SOCKET RIGHTS 7>
  #
  # _maxmesglen_ and _maxcontrollen_ can be nil.
  # In that case, the buffer will be grown until the message is not truncated.
  # Internally, MSG_PEEK is used.
  # Buffer full and MSG_CTRUNC are checked for truncation.
  #
  # recvmsg can be used to implement recv_io as follows:
  #
  #   mesg, sender_sockaddr, rflags, *controls = sock.recvmsg(:scm_rights=>true)
  #   controls.each {|ancdata|
  #     if ancdata.cmsg_is?(:SOCKET, :RIGHTS)
  #       return ancdata.unix_rights[0]
  #     end
  #   }
  def recvmsg(dlen = nil, flags = 0, clen = nil, scm_rights: false)
    __recvmsg(dlen, flags, clen, scm_rights)
  end

  # call-seq:
  #    basicsocket.recvmsg_nonblock(maxdatalen=nil, flags=0, maxcontrollen=nil, opts={}) => [data, sender_addrinfo, rflags, *controls]
  #
  # recvmsg receives a message using recvmsg(2) system call in non-blocking manner.
  #
  # It is similar to BasicSocket#recvmsg
  # but non-blocking flag is set before the system call
  # and it doesn't retry the system call.
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that recvmsg_nonblock should not raise an IO::WaitReadable exception, but
  # return the symbol +:wait_readable+ instead.
  def recvmsg_nonblock(dlen = nil, flags = 0, clen = nil,
                       scm_rights: false, exception: true)
    __recvmsg_nonblock(dlen, flags, clen, scm_rights, exception)
  end

  # Linux-specific optimizations to avoid fcntl for IO#read_nonblock
  # and IO#write_nonblock using MSG_DONTWAIT
  # Do other platforms support MSG_DONTWAIT reliably?
  if RUBY_PLATFORM =~ /linux/ && Socket.const_defined?(:MSG_DONTWAIT)
    def read_nonblock(len, str = nil, exception: true) # :nodoc:
      __read_nonblock(len, str, exception)
    end

    def write_nonblock(buf, exception: true) # :nodoc:
      __write_nonblock(buf, exception)
    end
  end
end

class Socket < BasicSocket
  # enable the socket option IPV6_V6ONLY if IPV6_V6ONLY is available.
  def ipv6only!
    if defined? Socket::IPV6_V6ONLY
      self.setsockopt(:IPV6, :V6ONLY, 1)
    end
  end

  # call-seq:
  #   socket.recvfrom_nonblock(maxlen[, flags[, outbuf[, opts]]]) => [mesg, sender_addrinfo]
  #
  # Receives up to _maxlen_ bytes from +socket+ using recvfrom(2) after
  # O_NONBLOCK is set for the underlying file descriptor.
  # _flags_ is zero or more of the +MSG_+ options.
  # The first element of the results, _mesg_, is the data received.
  # The second element, _sender_addrinfo_, contains protocol-specific address
  # information of the sender.
  #
  # When recvfrom(2) returns 0, Socket#recv_nonblock returns nil.
  # In most cases it means the connection was closed, but for UDP connections
  # it may mean an empty packet was received, as the underlying API makes
  # it impossible to distinguish these two cases.
  #
  # === Parameters
  # * +maxlen+ - the maximum number of bytes to receive from the socket
  # * +flags+ - zero or more of the +MSG_+ options
  # * +outbuf+ - destination String buffer
  # * +opts+ - keyword hash, supporting `exception: false`
  #
  # === Example
  #   # In one file, start this first
  #   require 'socket'
  #   include Socket::Constants
  #   socket = Socket.new(AF_INET, SOCK_STREAM, 0)
  #   sockaddr = Socket.sockaddr_in(2200, 'localhost')
  #   socket.bind(sockaddr)
  #   socket.listen(5)
  #   client, client_addrinfo = socket.accept
  #   begin # emulate blocking recvfrom
  #     pair = client.recvfrom_nonblock(20)
  #   rescue IO::WaitReadable
  #     IO.select([client])
  #     retry
  #   end
  #   data = pair[0].chomp
  #   puts "I only received 20 bytes '#{data}'"
  #   sleep 1
  #   socket.close
  #
  #   # In another file, start this second
  #   require 'socket'
  #   include Socket::Constants
  #   socket = Socket.new(AF_INET, SOCK_STREAM, 0)
  #   sockaddr = Socket.sockaddr_in(2200, 'localhost')
  #   socket.connect(sockaddr)
  #   socket.puts "Watch this get cut short!"
  #   socket.close
  #
  # Refer to Socket#recvfrom for the exceptions that may be thrown if the call
  # to _recvfrom_nonblock_ fails.
  #
  # Socket#recvfrom_nonblock may raise any error corresponding to recvfrom(2) failure,
  # including Errno::EWOULDBLOCK.
  #
  # If the exception is Errno::EWOULDBLOCK or Errno::EAGAIN,
  # it is extended by IO::WaitReadable.
  # So IO::WaitReadable can be used to rescue the exceptions for retrying
  # recvfrom_nonblock.
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that recvfrom_nonblock should not raise an IO::WaitReadable exception, but
  # return the symbol +:wait_readable+ instead.
  #
  # === See
  # * Socket#recvfrom
  def recvfrom_nonblock(len, flag = 0, str = nil, exception: true)
    __recvfrom_nonblock(len, flag, str, exception)
  end

  # call-seq:
  #   socket.accept_nonblock([options]) => [client_socket, client_addrinfo]
  #
  # Accepts an incoming connection using accept(2) after
  # O_NONBLOCK is set for the underlying file descriptor.
  # It returns an array containing the accepted socket
  # for the incoming connection, _client_socket_,
  # and an Addrinfo, _client_addrinfo_.
  #
  # === Example
  #   # In one script, start this first
  #   require 'socket'
  #   include Socket::Constants
  #   socket = Socket.new(AF_INET, SOCK_STREAM, 0)
  #   sockaddr = Socket.sockaddr_in(2200, 'localhost')
  #   socket.bind(sockaddr)
  #   socket.listen(5)
  #   begin # emulate blocking accept
  #     client_socket, client_addrinfo = socket.accept_nonblock
  #   rescue IO::WaitReadable, Errno::EINTR
  #     IO.select([socket])
  #     retry
  #   end
  #   puts "The client said, '#{client_socket.readline.chomp}'"
  #   client_socket.puts "Hello from script one!"
  #   socket.close
  #
  #   # In another script, start this second
  #   require 'socket'
  #   include Socket::Constants
  #   socket = Socket.new(AF_INET, SOCK_STREAM, 0)
  #   sockaddr = Socket.sockaddr_in(2200, 'localhost')
  #   socket.connect(sockaddr)
  #   socket.puts "Hello from script 2."
  #   puts "The server said, '#{socket.readline.chomp}'"
  #   socket.close
  #
  # Refer to Socket#accept for the exceptions that may be thrown if the call
  # to _accept_nonblock_ fails.
  #
  # Socket#accept_nonblock may raise any error corresponding to accept(2) failure,
  # including Errno::EWOULDBLOCK.
  #
  # If the exception is Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::ECONNABORTED or Errno::EPROTO,
  # it is extended by IO::WaitReadable.
  # So IO::WaitReadable can be used to rescue the exceptions for retrying accept_nonblock.
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that accept_nonblock should not raise an IO::WaitReadable exception, but
  # return the symbol +:wait_readable+ instead.
  #
  # === See
  # * Socket#accept
  def accept_nonblock(exception: true)
    __accept_nonblock(exception)
  end

  RESOLUTION_DELAY = 0.05
  private_constant :RESOLUTION_DELAY

  CONNECTION_ATTEMPT_DELAY = 0.25
  private_constant :CONNECTION_ATTEMPT_DELAY

  ADDRESS_FAMILIES = {
    ipv6: Socket::AF_INET6,
    ipv4: Socket::AF_INET
  }.freeze
  private_constant :ADDRESS_FAMILIES

  HOSTNAME_RESOLUTION_QUEUE_UPDATED = 0
  private_constant :HOSTNAME_RESOLUTION_QUEUE_UPDATED

  IPV6_ADDRESS_FORMAT = /\A(?i:(?:(?:[0-9A-F]{1,4}:){7}(?:[0-9A-F]{1,4}|:)|(?:[0-9A-F]{1,4}:){6}(?:[0-9A-F]{1,4}|:(?:[0-9A-F]{1,4}:){1,5}[0-9A-F]{1,4}|:)|(?:[0-9A-F]{1,4}:){5}(?:(?::[0-9A-F]{1,4}){1,2}|:(?:[0-9A-F]{1,4}:){1,4}[0-9A-F]{1,4}|:)|(?:[0-9A-F]{1,4}:){4}(?:(?::[0-9A-F]{1,4}){1,3}|:(?:[0-9A-F]{1,4}:){1,3}[0-9A-F]{1,4}|:)|(?:[0-9A-F]{1,4}:){3}(?:(?::[0-9A-F]{1,4}){1,4}|:(?:[0-9A-F]{1,4}:){1,2}[0-9A-F]{1,4}|:)|(?:[0-9A-F]{1,4}:){2}(?:(?::[0-9A-F]{1,4}){1,5}|:(?:[0-9A-F]{1,4}:)[0-9A-F]{1,4}|:)|(?:[0-9A-F]{1,4}:){1}(?:(?::[0-9A-F]{1,4}){1,6}|:(?:[0-9A-F]{1,4}:){0,5}[0-9A-F]{1,4}|:)|(?:::(?:[0-9A-F]{1,4}:){0,7}[0-9A-F]{1,4}|::)))(?:%.+)?\z/
  private_constant :IPV6_ADDRESS_FORMAT

  # :call-seq:
  #   Socket.tcp(host, port, local_host=nil, local_port=nil, [opts]) {|socket| ... }
  #   Socket.tcp(host, port, local_host=nil, local_port=nil, [opts])
  #
  # creates a new socket object connected to host:port using TCP/IP.
  #
  # Starting from Ruby 3.4, this method operates according to the
  # Happy Eyeballs Version 2 ({RFC 8305}[https://datatracker.ietf.org/doc/html/rfc8305])
  # algorithm by default.
  #
  # For details on Happy Eyeballs Version 2,
  # see {Socket.tcp_fast_fallback=}[rdoc-ref:Socket.tcp_fast_fallback=].
  #
  # To make it behave the same as in Ruby 3.3 and earlier,
  # explicitly specify the option fast_fallback:false.
  # Or, setting Socket.tcp_fast_fallback=false will disable
  # Happy Eyeballs Version 2 not only for this method but for all Socket globally.
  #
  # If local_host:local_port is given,
  # the socket is bound to it.
  #
  # The optional last argument _opts_ is options represented by a hash.
  # _opts_ may have following options:
  #
  # [:resolv_timeout] Specifies the timeout in seconds from when the hostname resolution starts.
  # [:connect_timeout] This method sequentially attempts connecting to all candidate destination addresses.<br>The +connect_timeout+ specifies the timeout in seconds from the start of the connection attempt to the last candidate.<br>By default, all connection attempts continue until the timeout occurs.<br>When +fast_fallback:false+ is explicitly specified,<br>a timeout is set for each connection attempt and any connection attempt that exceeds its timeout will be canceled.
  # [:open_timeout] Specifies the timeout in seconds from the start of the method execution.<br>If this timeout is reached while there are still addresses that have not yet been attempted for connection, no further attempts will be made.
  # [:fast_fallback] Enables the Happy Eyeballs Version 2 algorithm (enabled by default).
  #
  # If a block is given, the block is called with the socket.
  # The value of the block is returned.
  # The socket is closed when this method returns.
  #
  # If no block is given, the socket is returned.
  #
  #   Socket.tcp("www.ruby-lang.org", 80) {|sock|
  #     sock.print "GET / HTTP/1.0\r\nHost: www.ruby-lang.org\r\n\r\n"
  #     sock.close_write
  #     puts sock.read
  #   }
  def self.tcp(host, port, local_host = nil, local_port = nil, connect_timeout: nil, resolv_timeout: nil, open_timeout: nil, fast_fallback: tcp_fast_fallback, &) # :yield: socket

    if open_timeout && (connect_timeout || resolv_timeout)
      raise ArgumentError, "Cannot specify open_timeout along with connect_timeout or resolv_timeout"
    end

    sock = if fast_fallback && !(host && ip_address?(host))
      tcp_with_fast_fallback(host, port, local_host, local_port, connect_timeout:, resolv_timeout:, open_timeout:)
    else
      tcp_without_fast_fallback(host, port, local_host, local_port, connect_timeout:, resolv_timeout:, open_timeout:)
    end

    if block_given?
      begin
        yield sock
      ensure
        sock.close
      end
    else
      sock
    end
  end

  def self.tcp_with_fast_fallback(host, port, local_host = nil, local_port = nil, connect_timeout: nil, resolv_timeout: nil, open_timeout: nil)
    if local_host || local_port
      local_addrinfos = Addrinfo.getaddrinfo(local_host, local_port, nil, :STREAM, timeout: resolv_timeout)
      resolving_family_names = local_addrinfos.map { |lai| ADDRESS_FAMILIES.key(lai.afamily) }.uniq
    else
      local_addrinfos = []
      resolving_family_names = ADDRESS_FAMILIES.keys
    end

    hostname_resolution_threads = []
    resolution_store = HostnameResolutionStore.new(resolving_family_names)
    connecting_sockets = {}
    is_windows_environment ||= (RUBY_PLATFORM =~ /mswin|mingw|cygwin/)

    now = current_clock_time
    resolution_delay_expires_at = nil
    connection_attempt_delay_expires_at = nil
    user_specified_connect_timeout_at = nil
    user_specified_open_timeout_at = open_timeout ? now + open_timeout : nil
    last_error = nil
    last_error_from_thread = false

    if resolving_family_names.size == 1
      family_name = resolving_family_names.first
      addrinfos = Addrinfo.getaddrinfo(host, port, family_name, :STREAM, timeout: resolv_timeout)
      resolution_store.add_resolved(family_name, addrinfos)
      hostname_resolution_result = nil
      hostname_resolution_notifier = nil
      user_specified_resolv_timeout_at = nil
    else
      hostname_resolution_result = HostnameResolutionResult.new(resolving_family_names.size)
      hostname_resolution_notifier = hostname_resolution_result.notifier

      hostname_resolution_threads.concat(
        resolving_family_names.map { |family|
          thread_args = [family, host, port, hostname_resolution_result]
          thread = Thread.new(*thread_args) { |*thread_args| resolve_hostname(*thread_args) }
          Thread.pass
          thread
        }
      )

      user_specified_resolv_timeout_at = resolv_timeout ? now + resolv_timeout : Float::INFINITY
    end

    loop do
      if resolution_store.any_addrinfos? &&
          !resolution_delay_expires_at &&
          !connection_attempt_delay_expires_at
        while (addrinfo = resolution_store.get_addrinfo)
          if local_addrinfos.any?
            local_addrinfo = local_addrinfos.find { |lai| lai.afamily == addrinfo.afamily }

            if local_addrinfo.nil? # Connecting addrinfoと同じアドレスファミリのLocal addrinfoがない
              if resolution_store.any_addrinfos?
                # Try other Addrinfo in next "while"
                next
              elsif connecting_sockets.any? || resolution_store.any_unresolved_family?
                # Exit this "while" and wait for connections to be established or hostname resolution in next loop
                # Or exit this "while" and wait for hostname resolution in next loop
                break
              else
                raise SocketError.new 'no appropriate local address'
              end
            end
          end

          begin
            if resolution_store.any_addrinfos? ||
               connecting_sockets.any? ||
               resolution_store.any_unresolved_family?
              socket = Socket.new(addrinfo.pfamily, addrinfo.socktype, addrinfo.protocol)
              socket.bind(local_addrinfo) if local_addrinfo
              result = socket.connect_nonblock(addrinfo, exception: false)
            else
              result = socket = local_addrinfo ?
                addrinfo.connect_from(local_addrinfo, timeout: connect_timeout) :
                addrinfo.connect(timeout: connect_timeout)
            end

            if result == :wait_writable
              connection_attempt_delay_expires_at = now + CONNECTION_ATTEMPT_DELAY
              if resolution_store.empty_addrinfos?
                user_specified_connect_timeout_at = connect_timeout ? now + connect_timeout : Float::INFINITY
              end

              connecting_sockets[socket] = addrinfo
              break
            else
              return socket # connection established
            end
          rescue SystemCallError => e
            socket&.close
            last_error = e

            if resolution_store.any_addrinfos?
              # Try other Addrinfo in next "while"
              next
            elsif connecting_sockets.any? || resolution_store.any_unresolved_family?
              # Exit this "while" and wait for connections to be established or hostname resolution in next loop
              # Or exit this "while" and wait for hostname resolution in next loop
              break
            else
              raise last_error
            end
          end
        end
      end

      ends_at =
        if resolution_store.any_addrinfos?
          [(resolution_delay_expires_at || connection_attempt_delay_expires_at),
           user_specified_open_timeout_at].compact.min
        elsif user_specified_open_timeout_at
          user_specified_open_timeout_at
        else
          [user_specified_resolv_timeout_at, user_specified_connect_timeout_at].compact.max
        end

      hostname_resolved, writable_sockets, except_sockets = IO.select(
        hostname_resolution_notifier,
        connecting_sockets.keys,
        # Use errorfds to wait for non-blocking connect failures on Windows
        is_windows_environment ? connecting_sockets.keys : nil,
        second_to_timeout(current_clock_time, ends_at),
      )
      now = current_clock_time
      resolution_delay_expires_at = nil if expired?(now, resolution_delay_expires_at)
      connection_attempt_delay_expires_at = nil if expired?(now, connection_attempt_delay_expires_at)

      if writable_sockets&.any?
        while (writable_socket = writable_sockets.pop)
          is_connected = is_windows_environment || (
            sockopt = writable_socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR)
            sockopt.int.zero?
          )

          if is_connected
            connecting_sockets.delete writable_socket
            return writable_socket
          else
            failed_ai = connecting_sockets.delete writable_socket
            writable_socket.close
            ip_address = failed_ai.ipv6? ? "[#{failed_ai.ip_address}]" : failed_ai.ip_address
            last_error = SystemCallError.new("connect(2) for #{ip_address}:#{failed_ai.ip_port}", sockopt.int)

            if writable_sockets.any? || connecting_sockets.any?
              # Try other writable socket in next "while"
              # Or exit this "while" and wait for connections to be established or hostname resolution in next loop
            elsif resolution_store.any_addrinfos? || resolution_store.any_unresolved_family?
              # Exit this "while" and try other connection attempt
              # Or exit this "while" and wait for hostname resolution in next loop
              connection_attempt_delay_expires_at = nil
              user_specified_connect_timeout_at = nil
            else
              raise last_error
            end
          end
        end
      end

      if except_sockets&.any?
        except_sockets.each do |except_socket|
          failed_ai = connecting_sockets.delete except_socket
          sockopt = except_socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR)
          except_socket.close
          ip_address = failed_ai.ipv6? ? "[#{failed_ai.ip_address}]" : failed_ai.ip_address
          last_error = SystemCallError.new("connect(2) for #{ip_address}:#{failed_ai.ip_port}", sockopt.int)

          if except_sockets.any? || connecting_sockets.any?
            # Cleanup other except socket in next "each"
            # Or exit this "while" and wait for connections to be established or hostname resolution in next loop
          elsif resolution_store.any_addrinfos? || resolution_store.any_unresolved_family?
            # Exit this "while" and try other connection attempt
            # Or exit this "while" and wait for hostname resolution in next loop
            connection_attempt_delay_expires_at = nil
            user_specified_connect_timeout_at = nil
          else
            raise last_error
          end
        end
      end

      if hostname_resolved&.any?
        while (family_and_result = hostname_resolution_result.get)
          family_name, result = family_and_result

          if result.is_a? Exception
            resolution_store.add_error(family_name, result)

            unless (Socket.const_defined?(:EAI_ADDRFAMILY)) &&
              (result.is_a?(Socket::ResolutionError)) &&
              (result.error_code == Socket::EAI_ADDRFAMILY)
              other = family_name == :ipv6 ? :ipv4 : :ipv6
              if !resolution_store.resolved?(other) || !resolution_store.resolved_successfully?(other)
                last_error = result
                last_error_from_thread = true
              end
            end
          else
            resolution_store.add_resolved(family_name, result)
          end
        end

        if resolution_store.resolved?(:ipv4)
          if resolution_store.resolved?(:ipv6)
            hostname_resolution_notifier = nil
            resolution_delay_expires_at = nil
            user_specified_resolv_timeout_at = nil
          elsif resolution_store.resolved_successfully?(:ipv4)
            resolution_delay_expires_at = now + RESOLUTION_DELAY
          end
        end
      end

      raise(Errno::ETIMEDOUT, 'user specified timeout') if expired?(now, user_specified_open_timeout_at)

      if resolution_store.empty_addrinfos?
        if connecting_sockets.empty? && resolution_store.resolved_all_families?
          if last_error_from_thread
            raise last_error.class, last_error.message, cause: last_error
          else
            raise last_error
          end
        end

        if (expired?(now, user_specified_resolv_timeout_at) || resolution_store.resolved_all_families?) &&
           (expired?(now, user_specified_connect_timeout_at) || connecting_sockets.empty?)
          raise Errno::ETIMEDOUT, 'user specified timeout'
        end
      end
    end
  ensure
    hostname_resolution_threads.each do |thread|
      thread.exit
    end

    hostname_resolution_result&.close

    connecting_sockets.each_key do |connecting_socket|
      connecting_socket.close
    end
  end

  def self.tcp_without_fast_fallback(host, port, local_host, local_port, connect_timeout:, resolv_timeout:, open_timeout:)
    last_error = nil
    ret = nil

    local_addr_list = nil
    if local_host != nil || local_port != nil
      local_addr_list = Addrinfo.getaddrinfo(local_host, local_port, nil, :STREAM, nil)
    end

    timeout = open_timeout ? open_timeout : resolv_timeout
    starts_at = current_clock_time

    Addrinfo.foreach(host, port, nil, :STREAM, timeout:) {|ai|
      if local_addr_list
        local_addr = local_addr_list.find {|local_ai| local_ai.afamily == ai.afamily }
        next unless local_addr
      else
        local_addr = nil
      end
      begin
        timeout = open_timeout ? open_timeout - (current_clock_time - starts_at) : connect_timeout
        sock = local_addr ?
          ai.connect_from(local_addr, timeout:) :
          ai.connect(timeout:)
      rescue SystemCallError
        last_error = $!
        next
      end
      ret = sock
      break
    }
    unless ret
      if last_error
        raise last_error
      else
        raise SocketError, "no appropriate local address"
      end
    end

    ret
  end
  private_class_method :tcp_without_fast_fallback

  def self.ip_address?(hostname)
    hostname.match?(IPV6_ADDRESS_FORMAT) || hostname.match?(/\A([0-9]{1,3}\.){3}[0-9]{1,3}\z/)
  end
  private_class_method :ip_address?

  def self.resolve_hostname(family, host, port, hostname_resolution_result)
    begin
      resolved_addrinfos = Addrinfo.getaddrinfo(host, port, ADDRESS_FAMILIES[family], :STREAM)
      hostname_resolution_result.add(family, resolved_addrinfos)
    rescue => e
      hostname_resolution_result.add(family, e)
    end
  end
  private_class_method :resolve_hostname

  def self.current_clock_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
  private_class_method :current_clock_time

  def self.second_to_timeout(started_at, ends_at)
    return nil if ends_at == Float::INFINITY || ends_at.nil?

    remaining = (ends_at - started_at)
    remaining.negative? ? 0 : remaining
  end
  private_class_method :second_to_timeout

  def self.expired?(started_at, ends_at)
    second_to_timeout(started_at, ends_at)&.zero?
  end
  private_class_method :expired?

  class HostnameResolutionResult
    def initialize(size)
      @size = size
      @taken_count = 0
      @rpipe, @wpipe = IO.pipe
      @results = []
      @mutex = Mutex.new
    end

    def notifier
      [@rpipe]
    end

    def add(family, result)
      @mutex.synchronize do
        @results.push [family, result]
        @wpipe.putc HOSTNAME_RESOLUTION_QUEUE_UPDATED
      end
    end

    def get
      return nil if @results.empty?

      res = nil

      @mutex.synchronize do
        @rpipe.getbyte
        res = @results.shift
      end

      @taken_count += 1
      close if @taken_count == @size
      res
    end

    def close
      @rpipe.close
      @wpipe.close
    end
  end
  private_constant :HostnameResolutionResult

  class HostnameResolutionStore
    PRIORITY_ON_V6 = [:ipv6, :ipv4].freeze
    PRIORITY_ON_V4 = [:ipv4, :ipv6].freeze

    def initialize(family_names)
      @family_names = family_names
      @addrinfo_dict = {}
      @error_dict = {}
      @last_family = nil
    end

    def add_resolved(family_name, addrinfos)
      @addrinfo_dict[family_name] = addrinfos
    end

    def add_error(family_name, error)
      @addrinfo_dict[family_name] = []
      @error_dict[family_name] = error
    end

    def get_addrinfo
      precedences =
        case @last_family
        when :ipv4, nil then PRIORITY_ON_V6
        when :ipv6      then PRIORITY_ON_V4
        end

      precedences.each do |family_name|
        addrinfo = @addrinfo_dict[family_name]&.shift
        next unless addrinfo

        @last_family = family_name
        return addrinfo
      end

      nil
    end

    def empty_addrinfos?
      @addrinfo_dict.all? { |_, addrinfos| addrinfos.empty? }
    end

    def any_addrinfos?
      !empty_addrinfos?
    end

    def resolved?(family)
      @addrinfo_dict.has_key? family
    end

    def resolved_successfully?(family)
      resolved?(family) && !@error_dict[family]
    end

    def resolved_all_families?
      (@family_names - @addrinfo_dict.keys).empty?
    end

    def any_unresolved_family?
      !resolved_all_families?
    end
  end
  private_constant :HostnameResolutionStore

  # :stopdoc:
  def self.ip_sockets_port0(ai_list, reuseaddr)
    sockets = []
    begin
      sockets.clear
      port = nil
      ai_list.each {|ai|
        begin
          s = Socket.new(ai.pfamily, ai.socktype, ai.protocol)
        rescue SystemCallError
          next
        end
        sockets << s
        s.ipv6only! if ai.ipv6?
        if reuseaddr
          s.setsockopt(:SOCKET, :REUSEADDR, 1)
        end
        unless port
          s.bind(ai)
          port = s.local_address.ip_port
        else
          s.bind(ai.family_addrinfo(ai.ip_address, port))
        end
      }
    rescue Errno::EADDRINUSE
      sockets.each(&:close)
      retry
    rescue Exception
      sockets.each(&:close)
      raise
    end
    sockets
  end
  class << self
    private :ip_sockets_port0
  end

  def self.tcp_server_sockets_port0(host)
    ai_list = Addrinfo.getaddrinfo(host, 0, nil, :STREAM, nil, Socket::AI_PASSIVE)
    sockets = ip_sockets_port0(ai_list, true)
    begin
      sockets.each {|s|
        s.listen(Socket::SOMAXCONN)
      }
    rescue Exception
      sockets.each(&:close)
      raise
    end
    sockets
  end
  class << self
    private :tcp_server_sockets_port0
  end
  # :startdoc:

  # creates TCP/IP server sockets for _host_ and _port_.
  # _host_ is optional.
  #
  # If no block given,
  # it returns an array of listening sockets.
  #
  # If a block is given, the block is called with the sockets.
  # The value of the block is returned.
  # The socket is closed when this method returns.
  #
  # If _port_ is 0, actual port number is chosen dynamically.
  # However all sockets in the result has same port number.
  #
  #   # tcp_server_sockets returns two sockets.
  #   sockets = Socket.tcp_server_sockets(1296)
  #   p sockets #=> [#<Socket:fd 3>, #<Socket:fd 4>]
  #
  #   # The sockets contains IPv6 and IPv4 sockets.
  #   sockets.each {|s| p s.local_address }
  #   #=> #<Addrinfo: [::]:1296 TCP>
  #   #   #<Addrinfo: 0.0.0.0:1296 TCP>
  #
  #   # IPv6 and IPv4 socket has same port number, 53114, even if it is chosen dynamically.
  #   sockets = Socket.tcp_server_sockets(0)
  #   sockets.each {|s| p s.local_address }
  #   #=> #<Addrinfo: [::]:53114 TCP>
  #   #   #<Addrinfo: 0.0.0.0:53114 TCP>
  #
  #   # The block is called with the sockets.
  #   Socket.tcp_server_sockets(0) {|sockets|
  #     p sockets #=> [#<Socket:fd 3>, #<Socket:fd 4>]
  #   }
  #
  def self.tcp_server_sockets(host=nil, port)
    if port == 0
      sockets = tcp_server_sockets_port0(host)
    else
      last_error = nil
      sockets = []
      begin
        Addrinfo.foreach(host, port, nil, :STREAM, nil, Socket::AI_PASSIVE) {|ai|
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
      rescue Exception
        sockets.each(&:close)
        raise
      end
    end
    if block_given?
      begin
        yield sockets
      ensure
        sockets.each(&:close)
      end
    else
      sockets
    end
  end

  # yield socket and client address for each a connection accepted via given sockets.
  #
  # The arguments are a list of sockets.
  # The individual argument should be a socket or an array of sockets.
  #
  # This method yields the block sequentially.
  # It means that the next connection is not accepted until the block returns.
  # So concurrent mechanism, thread for example, should be used to service multiple clients at a time.
  #
  def self.accept_loop(*sockets) # :yield: socket, client_addrinfo
    sockets.flatten!(1)
    if sockets.empty?
      raise ArgumentError, "no sockets"
    end
    loop {
      readable, _, _ = IO.select(sockets)
      readable.each {|r|
        sock, addr = r.accept_nonblock(exception: false)
        next if sock == :wait_readable
        yield sock, addr
      }
    }
  end

  # creates a TCP/IP server on _port_ and calls the block for each connection accepted.
  # The block is called with a socket and a client_address as an Addrinfo object.
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
  # Note that Addrinfo.getaddrinfo is used to determine the server socket addresses.
  # When Addrinfo.getaddrinfo returns two or more addresses,
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
  def self.tcp_server_loop(host=nil, port, &b) # :yield: socket, client_addrinfo
    tcp_server_sockets(host, port) {|sockets|
      accept_loop(sockets, &b)
    }
  end

  # :call-seq:
  #   Socket.udp_server_sockets([host, ] port)
  #
  # Creates UDP/IP sockets for a UDP server.
  #
  # If no block given, it returns an array of sockets.
  #
  # If a block is given, the block is called with the sockets.
  # The value of the block is returned.
  # The sockets are closed when this method returns.
  #
  # If _port_ is zero, some port is chosen.
  # But the chosen port is used for the all sockets.
  #
  #   # UDP/IP echo server
  #   Socket.udp_server_sockets(0) {|sockets|
  #     p sockets.first.local_address.ip_port     #=> 32963
  #     Socket.udp_server_loop_on(sockets) {|msg, msg_src|
  #       msg_src.reply msg
  #     }
  #   }
  #
  def self.udp_server_sockets(host=nil, port)
    last_error = nil
    sockets = []

    ipv6_recvpktinfo = nil
    if defined? Socket::AncillaryData
      if defined? Socket::IPV6_RECVPKTINFO # RFC 3542
        ipv6_recvpktinfo = Socket::IPV6_RECVPKTINFO
      elsif defined? Socket::IPV6_PKTINFO # RFC 2292
        ipv6_recvpktinfo = Socket::IPV6_PKTINFO
      end
    end

    local_addrs = Socket.ip_address_list

    ip_list = []
    Addrinfo.foreach(host, port, nil, :DGRAM, nil, Socket::AI_PASSIVE) {|ai|
      if ai.ipv4? && ai.ip_address == "0.0.0.0"
        local_addrs.each {|a|
          next unless a.ipv4?
          ip_list << Addrinfo.new(a.to_sockaddr, :INET, :DGRAM, 0);
        }
      elsif ai.ipv6? && ai.ip_address == "::" && !ipv6_recvpktinfo
        local_addrs.each {|a|
          next unless a.ipv6?
          ip_list << Addrinfo.new(a.to_sockaddr, :INET6, :DGRAM, 0);
        }
      else
        ip_list << ai
      end
    }
    ip_list.uniq!(&:to_sockaddr)

    if port == 0
      sockets = ip_sockets_port0(ip_list, false)
    else
      ip_list.each {|ip|
        ai = Addrinfo.udp(ip.ip_address, port)
        begin
          s = ai.bind
        rescue SystemCallError
          last_error = $!
          next
        end
        sockets << s
      }
      if sockets.empty?
        raise last_error
      end
    end

    sockets.each {|s|
      ai = s.local_address
      if ipv6_recvpktinfo && ai.ipv6? && ai.ip_address == "::"
        s.setsockopt(:IPV6, ipv6_recvpktinfo, 1)
      end
    }

    if block_given?
      begin
        yield sockets
      ensure
        sockets.each(&:close) if sockets
      end
    else
      sockets
    end
  end

  # :call-seq:
  #   Socket.udp_server_recv(sockets) {|msg, msg_src| ... }
  #
  # Receive UDP/IP packets from the given _sockets_.
  # For each packet received, the block is called.
  #
  # The block receives _msg_ and _msg_src_.
  # _msg_ is a string which is the payload of the received packet.
  # _msg_src_ is a Socket::UDPSource object which is used for reply.
  #
  # Socket.udp_server_loop can be implemented using this method as follows.
  #
  #   udp_server_sockets(host, port) {|sockets|
  #     loop {
  #       readable, _, _ = IO.select(sockets)
  #       udp_server_recv(readable) {|msg, msg_src| ... }
  #     }
  #   }
  #
  def self.udp_server_recv(sockets)
    sockets.each {|r|
      msg, sender_addrinfo, _, *controls = r.recvmsg_nonblock(exception: false)
      next if msg == :wait_readable
      ai = r.local_address
      if ai.ipv6? and pktinfo = controls.find {|c| c.cmsg_is?(:IPV6, :PKTINFO) }
        ai = Addrinfo.udp(pktinfo.ipv6_pktinfo_addr.ip_address, ai.ip_port)
        yield msg, UDPSource.new(sender_addrinfo, ai) {|reply_msg|
          r.sendmsg reply_msg, 0, sender_addrinfo, pktinfo
        }
      else
        yield msg, UDPSource.new(sender_addrinfo, ai) {|reply_msg|
          r.send reply_msg, 0, sender_addrinfo
        }
      end
    }
  end

  # :call-seq:
  #   Socket.udp_server_loop_on(sockets) {|msg, msg_src| ... }
  #
  # Run UDP/IP server loop on the given sockets.
  #
  # The return value of Socket.udp_server_sockets is appropriate for the argument.
  #
  # It calls the block for each message received.
  #
  def self.udp_server_loop_on(sockets, &b) # :yield: msg, msg_src
    loop {
      readable, _, _ = IO.select(sockets)
      udp_server_recv(readable, &b)
    }
  end

  # :call-seq:
  #   Socket.udp_server_loop(port) {|msg, msg_src| ... }
  #   Socket.udp_server_loop(host, port) {|msg, msg_src| ... }
  #
  # creates a UDP/IP server on _port_ and calls the block for each message arrived.
  # The block is called with the message and its source information.
  #
  # This method allocates sockets internally using _port_.
  # If _host_ is specified, it is used conjunction with _port_ to determine the server addresses.
  #
  # The _msg_ is a string.
  #
  # The _msg_src_ is a Socket::UDPSource object.
  # It is used for reply.
  #
  #   # UDP/IP echo server.
  #   Socket.udp_server_loop(9261) {|msg, msg_src|
  #     msg_src.reply msg
  #   }
  #
  def self.udp_server_loop(host=nil, port, &b) # :yield: message, message_source
    udp_server_sockets(host, port) {|sockets|
      udp_server_loop_on(sockets, &b)
    }
  end

  # UDP/IP address information used by Socket.udp_server_loop.
  class UDPSource
    # +remote_address+ is an Addrinfo object.
    #
    # +local_address+ is an Addrinfo object.
    #
    # +reply_proc+ is a Proc used to send reply back to the source.
    def initialize(remote_address, local_address, &reply_proc)
      @remote_address = remote_address
      @local_address = local_address
      @reply_proc = reply_proc
    end

    # Address of the source
    attr_reader :remote_address

    # Local address
    attr_reader :local_address

    def inspect # :nodoc:
      "\#<#{self.class}: #{@remote_address.inspect_sockaddr} to #{@local_address.inspect_sockaddr}>".dup
    end

    # Sends the String +msg+ to the source
    def reply(msg)
      @reply_proc.call msg
    end
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
    addr = Addrinfo.unix(path)
    sock = addr.connect
    if block_given?
      begin
        yield sock
      ensure
        sock.close
      end
    else
      sock
    end
  end

  # creates a UNIX server socket on _path_
  #
  # If no block given, it returns a listening socket.
  #
  # If a block is given, it is called with the socket and the block value is returned.
  # When the block exits, the socket is closed and the socket file is removed.
  #
  #   socket = Socket.unix_server_socket("/tmp/s")
  #   p socket                  #=> #<Socket:fd 3>
  #   p socket.local_address    #=> #<Addrinfo: /tmp/s SOCK_STREAM>
  #
  #   Socket.unix_server_socket("/tmp/sock") {|s|
  #     p s                     #=> #<Socket:fd 3>
  #     p s.local_address       #=> # #<Addrinfo: /tmp/sock SOCK_STREAM>
  #   }
  #
  def self.unix_server_socket(path)
    unless unix_socket_abstract_name?(path)
      begin
        st = File.lstat(path)
      rescue Errno::ENOENT
      end
      if st&.socket? && st.owned?
        File.unlink path
      end
    end
    s = Addrinfo.unix(path).listen
    if block_given?
      begin
        yield s
      ensure
        s.close
        unless unix_socket_abstract_name?(path)
          File.unlink path
        end
      end
    else
      s
    end
  end

  class << self
    private

    def unix_socket_abstract_name?(path)
      /linux/ =~ RUBY_PLATFORM && /\A(\0|\z)/ =~ path
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
  def self.unix_server_loop(path, &b) # :yield: socket, client_addrinfo
    unix_server_socket(path) {|serv|
      accept_loop(serv, &b)
    }
  end

  # call-seq:
  #   socket.connect_nonblock(remote_sockaddr, [options]) => 0
  #
  # Requests a connection to be made on the given +remote_sockaddr+ after
  # O_NONBLOCK is set for the underlying file descriptor.
  # Returns 0 if successful, otherwise an exception is raised.
  #
  # === Parameter
  # * +remote_sockaddr+ - the +struct+ sockaddr contained in a string or Addrinfo object
  #
  # === Example:
  #   # Pull down Google's web page
  #   require 'socket'
  #   include Socket::Constants
  #   socket = Socket.new(AF_INET, SOCK_STREAM, 0)
  #   sockaddr = Socket.sockaddr_in(80, 'www.google.com')
  #   begin # emulate blocking connect
  #     socket.connect_nonblock(sockaddr)
  #   rescue IO::WaitWritable
  #     IO.select(nil, [socket]) # wait 3-way handshake completion
  #     begin
  #       socket.connect_nonblock(sockaddr) # check connection failure
  #     rescue Errno::EISCONN
  #     end
  #   end
  #   socket.write("GET / HTTP/1.0\r\n\r\n")
  #   results = socket.read
  #
  # Refer to Socket#connect for the exceptions that may be thrown if the call
  # to _connect_nonblock_ fails.
  #
  # Socket#connect_nonblock may raise any error corresponding to connect(2) failure,
  # including Errno::EINPROGRESS.
  #
  # If the exception is Errno::EINPROGRESS,
  # it is extended by IO::WaitWritable.
  # So IO::WaitWritable can be used to rescue the exceptions for retrying connect_nonblock.
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that connect_nonblock should not raise an IO::WaitWritable exception, but
  # return the symbol +:wait_writable+ instead.
  #
  # === See
  # * Socket#connect
  def connect_nonblock(addr, exception: true)
    __connect_nonblock(addr, exception)
  end
end

class UDPSocket < IPSocket

  # call-seq:
  #   udpsocket.recvfrom_nonblock(maxlen [, flags[, outbuf [, options]]]) => [mesg, sender_inet_addr]
  #
  # Receives up to _maxlen_ bytes from +udpsocket+ using recvfrom(2) after
  # O_NONBLOCK is set for the underlying file descriptor.
  # _flags_ is zero or more of the +MSG_+ options.
  # The first element of the results, _mesg_, is the data received.
  # The second element, _sender_inet_addr_, is an array to represent the sender address.
  #
  # When recvfrom(2) returns 0, Socket#recv_nonblock returns nil.
  # In most cases it means the connection was closed, but it may also mean
  # an empty packet was received, as the underlying API makes
  # it impossible to distinguish these two cases.
  #
  # === Parameters
  # * +maxlen+ - the number of bytes to receive from the socket
  # * +flags+ - zero or more of the +MSG_+ options
  # * +outbuf+ - destination String buffer
  # * +options+ - keyword hash, supporting `exception: false`
  #
  # === Example
  # 	require 'socket'
  # 	s1 = UDPSocket.new
  # 	s1.bind("127.0.0.1", 0)
  # 	s2 = UDPSocket.new
  # 	s2.bind("127.0.0.1", 0)
  # 	s2.connect(*s1.addr.values_at(3,1))
  # 	s1.connect(*s2.addr.values_at(3,1))
  # 	s1.send "aaa", 0
  # 	begin # emulate blocking recvfrom
  # 	  p s2.recvfrom_nonblock(10)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]
  # 	rescue IO::WaitReadable
  # 	  IO.select([s2])
  # 	  retry
  # 	end
  #
  # Refer to Socket#recvfrom for the exceptions that may be thrown if the call
  # to _recvfrom_nonblock_ fails.
  #
  # UDPSocket#recvfrom_nonblock may raise any error corresponding to recvfrom(2) failure,
  # including Errno::EWOULDBLOCK.
  #
  # If the exception is Errno::EWOULDBLOCK or Errno::EAGAIN,
  # it is extended by IO::WaitReadable.
  # So IO::WaitReadable can be used to rescue the exceptions for retrying recvfrom_nonblock.
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that recvfrom_nonblock should not raise an IO::WaitReadable exception, but
  # return the symbol +:wait_readable+ instead.
  #
  # === See
  # * Socket#recvfrom
  def recvfrom_nonblock(len, flag = 0, outbuf = nil, exception: true)
    __recvfrom_nonblock(len, flag, outbuf, exception)
  end
end

class TCPServer < TCPSocket

  # call-seq:
  #   tcpserver.accept_nonblock([options]) => tcpsocket
  #
  # Accepts an incoming connection using accept(2) after
  # O_NONBLOCK is set for the underlying file descriptor.
  # It returns an accepted TCPSocket for the incoming connection.
  #
  # === Example
  # 	require 'socket'
  # 	serv = TCPServer.new(2202)
  # 	begin # emulate blocking accept
  # 	  sock = serv.accept_nonblock
  # 	rescue IO::WaitReadable, Errno::EINTR
  # 	  IO.select([serv])
  # 	  retry
  # 	end
  # 	# sock is an accepted socket.
  #
  # Refer to Socket#accept for the exceptions that may be thrown if the call
  # to TCPServer#accept_nonblock fails.
  #
  # TCPServer#accept_nonblock may raise any error corresponding to accept(2) failure,
  # including Errno::EWOULDBLOCK.
  #
  # If the exception is Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::ECONNABORTED, Errno::EPROTO,
  # it is extended by IO::WaitReadable.
  # So IO::WaitReadable can be used to rescue the exceptions for retrying accept_nonblock.
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that accept_nonblock should not raise an IO::WaitReadable exception, but
  # return the symbol +:wait_readable+ instead.
  #
  # === See
  # * TCPServer#accept
  # * Socket#accept
  def accept_nonblock(exception: true)
    __accept_nonblock(exception)
  end
end

class UNIXServer < UNIXSocket
  # call-seq:
  #   unixserver.accept_nonblock([options]) => unixsocket
  #
  # Accepts an incoming connection using accept(2) after
  # O_NONBLOCK is set for the underlying file descriptor.
  # It returns an accepted UNIXSocket for the incoming connection.
  #
  # === Example
  # 	require 'socket'
  # 	serv = UNIXServer.new("/tmp/sock")
  # 	begin # emulate blocking accept
  # 	  sock = serv.accept_nonblock
  # 	rescue IO::WaitReadable, Errno::EINTR
  # 	  IO.select([serv])
  # 	  retry
  # 	end
  # 	# sock is an accepted socket.
  #
  # Refer to Socket#accept for the exceptions that may be thrown if the call
  # to UNIXServer#accept_nonblock fails.
  #
  # UNIXServer#accept_nonblock may raise any error corresponding to accept(2) failure,
  # including Errno::EWOULDBLOCK.
  #
  # If the exception is Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::ECONNABORTED or Errno::EPROTO,
  # it is extended by IO::WaitReadable.
  # So IO::WaitReadable can be used to rescue the exceptions for retrying accept_nonblock.
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that accept_nonblock should not raise an IO::WaitReadable exception, but
  # return the symbol +:wait_readable+ instead.
  #
  # === See
  # * UNIXServer#accept
  # * Socket#accept
  def accept_nonblock(exception: true)
    __accept_nonblock(exception)
  end
end if defined?(UNIXSocket)
