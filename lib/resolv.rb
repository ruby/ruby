=begin
= resolv library
resolv.rb is a resolver library written in Ruby.
Since it is written in Ruby, it is thread-aware.
I.e. it can resolv many hostnames concurrently.

It is possible to lookup various resources of DNS using DNS module directly.

== example
  p Resolv.getaddress("www.ruby-lang.org")
  p Resolv.getname("210.251.121.214")

  Resolv::DNS.open {|dns|
    p dns.getresources("www.ruby-lang.org", Resolv::DNS::Resource::IN::A).collect {|r| r.address}
    p dns.getresources("ruby-lang.org", Resolv::DNS::Resource::IN::MX).collect {|r| [r.exchange.to_s, r.preference]}
  }

== Resolv class

=== class methods
--- Resolv.getaddress(name)
--- Resolv.getaddresses(name)
--- Resolv.each_address(name) {|address| ...}
    They lookups IP addresses of ((|name|)) which represents a hostname
    as a string by default resolver.

    getaddress returns first entry of lookupped addresses.
    getaddresses returns lookupped addresses as an array.
    each_address iterates over lookupped addresses.

--- Resolv.getname(address)
--- Resolv.getnames(address)
--- Resolv.each_name(address) {|name| ...}
    lookups hostnames of ((|address|)) which represents IP address as a string.

    getname returns first entry of lookupped names.
    getnames returns lookupped names as an array.
    each_names iterates over lookupped names.

== Resolv::Hosts class
hostname resolver using /etc/hosts format.

=== class methods
--- Resolv::Hosts.new(hosts='/etc/hosts')

=== methods
--- Resolv::Hosts#getaddress(name)
--- Resolv::Hosts#getaddresses(name)
--- Resolv::Hosts#each_address(name) {|address| ...}
    address lookup methods.

--- Resolv::Hosts#getname(address)
--- Resolv::Hosts#getnames(address)
--- Resolv::Hosts#each_name(address) {|name| ...}
    hostnames lookup methods.

== Resolv::DNS class
DNS stub resolver.

=== class methods
--- Resolv::DNS.new(config_info=nil)

    ((|config_info|)) should be nil, a string or a hash.
    If nil is given, /etc/resolv.conf and platform specific information is used.
    If a string is given, it should be a filename which format is same as /etc/resolv.conf.
    If a hash is given, it may contains information for nameserver, search and ndots as follows.

      Resolv::DNS.new({:nameserver=>["210.251.121.21"], :search=>["ruby-lang.org"], :ndots=>1})

--- Resolv::DNS.open(config_info=nil)
--- Resolv::DNS.open(config_info=nil) {|dns| ...}

=== methods
--- Resolv::DNS#close

--- Resolv::DNS#getaddress(name)
--- Resolv::DNS#getaddresses(name)
--- Resolv::DNS#each_address(name) {|address| ...}
    address lookup methods.

    ((|name|)) must be a instance of Resolv::DNS::Name or String.  Lookupped
    address is represented as an instance of Resolv::IPv4 or Resolv::IPv6.

--- Resolv::DNS#getname(address)
--- Resolv::DNS#getnames(address)
--- Resolv::DNS#each_name(address) {|name| ...}
    hostnames lookup methods.

    ((|address|)) must be a instance of Resolv::IPv4, Resolv::IPv6 or String.
    Lookupped name is represented as an instance of Resolv::DNS::Name.

--- Resolv::DNS#getresource(name, typeclass)
--- Resolv::DNS#getresources(name, typeclass)
--- Resolv::DNS#each_resource(name, typeclass) {|resource| ...}
    They lookup DNS resources of ((|name|)).
    ((|name|)) must be a instance of Resolv::Name or String.

    ((|typeclass|)) should be one of follows:
    * Resolv::DNS::Resource::IN::ANY
    * Resolv::DNS::Resource::IN::NS
    * Resolv::DNS::Resource::IN::CNAME
    * Resolv::DNS::Resource::IN::SOA
    * Resolv::DNS::Resource::IN::HINFO
    * Resolv::DNS::Resource::IN::MINFO
    * Resolv::DNS::Resource::IN::MX
    * Resolv::DNS::Resource::IN::TXT
    * Resolv::DNS::Resource::IN::ANY
    * Resolv::DNS::Resource::IN::A
    * Resolv::DNS::Resource::IN::WKS
    * Resolv::DNS::Resource::IN::PTR
    * Resolv::DNS::Resource::IN::AAAA

    Lookupped resource is represented as an instance of (a subclass of)
    Resolv::DNS::Resource. 
    (Resolv::DNS::Resource::IN::A, etc.)

== Resolv::DNS::Resource::IN::NS class
--- name
== Resolv::DNS::Resource::IN::CNAME class
--- name
== Resolv::DNS::Resource::IN::SOA class
--- mname
--- rname
--- serial
--- refresh
--- retry
--- expire
--- minimum
== Resolv::DNS::Resource::IN::HINFO class
--- cpu
--- os
== Resolv::DNS::Resource::IN::MINFO class
--- rmailbx
--- emailbx
== Resolv::DNS::Resource::IN::MX class
--- preference
--- exchange
== Resolv::DNS::Resource::IN::TXT class
--- data
== Resolv::DNS::Resource::IN::A class
--- address
== Resolv::DNS::Resource::IN::WKS class
--- address
--- protocol
--- bitmap
== Resolv::DNS::Resource::IN::PTR class
--- name
== Resolv::DNS::Resource::IN::AAAA class
--- address

== Resolv::DNS::Name class

=== class methods
--- Resolv::DNS::Name.create(name)

=== methods
--- Resolv::DNS::Name#to_s

== Resolv::DNS::Resource class

== Resolv::IPv4 class
=== class methods
--- Resolv::IPv4.create(address)

=== methods
--- Resolv::IPv4#to_s
--- Resolv::IPv4#to_name

=== constants
--- Resolv::IPv4::Regex
    regular expression for IPv4 address.

== Resolv::IPv6 class
=== class methods
--- Resolv::IPv6.create(address)

=== methods
--- Resolv::IPv6#to_s
--- Resolv::IPv6#to_name

=== constants
--- Resolv::IPv6::Regex
    regular expression for IPv6 address.

== Bugs
* NIS is not supported.
* /etc/nsswitch.conf is not supported.
* IPv6 is not supported.

=end

require 'socket'
require 'fcntl'
require 'timeout'
require 'thread'

begin
  require 'securerandom'
rescue LoadError
end

class Resolv
  def self.getaddress(name)
    DefaultResolver.getaddress(name)
  end

  def self.getaddresses(name)
    DefaultResolver.getaddresses(name)
  end

  def self.each_address(name, &block)
    DefaultResolver.each_address(name, &block)
  end

  def self.getname(address)
    DefaultResolver.getname(address)
  end

  def self.getnames(address)
    DefaultResolver.getnames(address)
  end

  def self.each_name(address, &proc)
    DefaultResolver.each_name(address, &proc)
  end

  def initialize(resolvers=[Hosts.new, DNS.new])
    @resolvers = resolvers
  end

  def getaddress(name)
    each_address(name) {|address| return address}
    raise ResolvError.new("no address for #{name}")
  end

  def getaddresses(name)
    ret = []
    each_address(name) {|address| ret << address}
    return ret
  end

  def each_address(name)
    if AddressRegex =~ name
      yield name
      return
    end
    yielded = false
    @resolvers.each {|r|
      r.each_address(name) {|address|
        yield address.to_s
        yielded = true
      }
      return if yielded
    }
  end

  def getname(address)
    each_name(address) {|name| return name}
    raise ResolvError.new("no name for #{address}")
  end

  def getnames(address)
    ret = []
    each_name(address) {|name| ret << name}
    return ret
  end

  def each_name(address)
    yielded = false
    @resolvers.each {|r|
      r.each_name(address) {|name|
        yield name.to_s
        yielded = true
      }
      return if yielded
    }
  end

  class ResolvError < StandardError
  end

  class ResolvTimeout < TimeoutError
  end

  class Hosts
    if /mswin32|mingw|bccwin/ =~ RUBY_PLATFORM
      require 'win32/resolv'
      DefaultFileName = Win32::Resolv.get_hosts_path
    else
      DefaultFileName = '/etc/hosts'
    end

    def initialize(filename = DefaultFileName)
      @filename = filename
      @mutex = Mutex.new
      @initialized = nil
    end

    def lazy_initialize
      @mutex.synchronize {
        unless @initialized
          @name2addr = {}
          @addr2name = {}
          open(@filename) {|f|
            f.each {|line|
              line.sub!(/#.*/, '')
              addr, hostname, *aliases = line.split(/\s+/)
              next unless addr
              addr.untaint
              hostname.untaint
              @addr2name[addr] = [] unless @addr2name.include? addr
              @addr2name[addr] << hostname
              @addr2name[addr] += aliases
              @name2addr[hostname] = [] unless @name2addr.include? hostname
              @name2addr[hostname] << addr
              aliases.each {|n|
                n.untaint
                @name2addr[n] = [] unless @name2addr.include? n
                @name2addr[n] << addr
              }
            }
          }
          @name2addr.each {|name, arr| arr.reverse!}
          @initialized = true
        end
      }
      self
    end

    def getaddress(name)
      each_address(name) {|address| return address}
      raise ResolvError.new("#{@filename} has no name: #{name}")
    end

    def getaddresses(name)
      ret = []
      each_address(name) {|address| ret << address}
      return ret
    end

    def each_address(name, &proc)
      lazy_initialize
      if @name2addr.include?(name)
        @name2addr[name].each(&proc)
      end
    end

    def getname(address)
      each_name(address) {|name| return name}
      raise ResolvError.new("#{@filename} has no address: #{address}")
    end

    def getnames(address)
      ret = []
      each_name(address) {|name| ret << name}
      return ret
    end

    def each_name(address, &proc)
      lazy_initialize
      if @addr2name.include?(address)
        @addr2name[address].each(&proc)
      end
    end
  end

  class DNS
    # STD0013 (RFC 1035, etc.)
    # ftp://ftp.isi.edu/in-notes/iana/assignments/dns-parameters

    Port = 53
    UDPSize = 512

    DNSThreadGroup = ThreadGroup.new

    def self.open(*args)
      dns = new(*args)
      return dns unless block_given?
      begin
        yield dns
      ensure
        dns.close
      end
    end

    def initialize(config_info=nil)
      @mutex = Mutex.new
      @config = Config.new(config_info)
      @initialized = nil
    end

    def lazy_initialize
      @mutex.synchronize {
        unless @initialized
          @config.lazy_initialize
          @initialized = true
        end
      }
      self
    end

    def close
      @mutex.synchronize {
        if @initialized
          @initialized = false
        end
      }
    end

    def getaddress(name)
      each_address(name) {|address| return address}
      raise ResolvError.new("DNS result has no information for #{name}")
    end

    def getaddresses(name)
      ret = []
      each_address(name) {|address| ret << address}
      return ret
    end

    def each_address(name)
      each_resource(name, Resource::IN::A) {|resource| yield resource.address}
    end

    def getname(address)
      each_name(address) {|name| return name}
      raise ResolvError.new("DNS result has no information for #{address}")
    end

    def getnames(address)
      ret = []
      each_name(address) {|name| ret << name}
      return ret
    end

    def each_name(address)
      case address
      when Name
        ptr = address
      when IPv4::Regex
        ptr = IPv4.create(address).to_name
      when IPv6::Regex
        ptr = IPv6.create(address).to_name
      else
        raise ResolvError.new("cannot interpret as address: #{address}")
      end
      each_resource(ptr, Resource::IN::PTR) {|resource| yield resource.name}
    end

    def getresource(name, typeclass)
      each_resource(name, typeclass) {|resource| return resource}
      raise ResolvError.new("DNS result has no information for #{name}")
    end

    def getresources(name, typeclass)
      ret = []
      each_resource(name, typeclass) {|resource| ret << resource}
      return ret
    end

    def each_resource(name, typeclass, &proc)
      lazy_initialize
      requester = make_requester
      senders = {}
      begin
        @config.resolv(name) {|candidate, tout, nameserver|
          msg = Message.new
          msg.rd = 1
          msg.add_question(candidate, typeclass)
          unless sender = senders[[candidate, nameserver]]
            sender = senders[[candidate, nameserver]] =
              requester.sender(msg, candidate, nameserver)
          end
          reply, reply_name = requester.request(sender, tout)
          case reply.rcode
          when RCode::NoError
            extract_resources(reply, reply_name, typeclass, &proc)
            return
          when RCode::NXDomain
            raise Config::NXDomain.new(reply_name.to_s)
          else
            raise Config::OtherResolvError.new(reply_name.to_s)
          end
        }
      ensure
        requester.close
      end
    end

    def make_requester # :nodoc:
      if nameserver = @config.single?
        Requester::ConnectedUDP.new(nameserver)
      else
        Requester::UnconnectedUDP.new
      end
    end

    def extract_resources(msg, name, typeclass)
      if typeclass < Resource::ANY
        n0 = Name.create(name)
        msg.each_answer {|n, ttl, data|
          yield data if n0 == n
        }
      end
      yielded = false
      n0 = Name.create(name)
      msg.each_answer {|n, ttl, data|
        if n0 == n
          case data
          when typeclass
            yield data
            yielded = true
          when Resource::CNAME
            n0 = data.name
          end
        end
      }
      return if yielded
      msg.each_answer {|n, ttl, data|
        if n0 == n
          case data
          when typeclass
            yield data
          end
        end
      }
    end

    if defined? SecureRandom
      def self.random(arg) # :nodoc:
        begin
          SecureRandom.random_number(arg)
        rescue NotImplementedError
          rand(arg)
        end
      end
    else
      def self.random(arg) # :nodoc:
        rand(arg)
      end
    end

    def self.rangerand(range) # :nodoc:
      base = range.begin
      len = range.end - range.begin
      if !range.exclude_end?
        len += 1
      end
      base + random(len)
    end

    RequestID = {}
    RequestIDMutex = Mutex.new

    def self.allocate_request_id(host, port) # :nodoc:
      id = nil
      RequestIDMutex.synchronize {
        h = (RequestID[[host, port]] ||= {})
        begin
          id = rangerand(0x0000..0xffff)
        end while h[id] 
        h[id] = true
      }
      id
    end

    def self.free_request_id(host, port, id) # :nodoc:
      RequestIDMutex.synchronize {
        key = [host, port]
        if h = RequestID[key]
          h.delete id
          if h.empty?
            RequestID.delete key
          end
        end
      }
    end

    def self.bind_random_port(udpsock) # :nodoc:
      begin
        port = rangerand(1024..65535)
        udpsock.bind("", port)
      rescue Errno::EADDRINUSE
        retry
      end
    end

    class Requester
      def initialize
        @senders = {}
        @sock = nil
      end

      def request(sender, tout)
        timelimit = Time.now + tout
        sender.send
        while (now = Time.now) < timelimit
          timeout = timelimit - now
          if !IO.select([@sock], nil, nil, timeout)
            raise ResolvTimeout
          end
          reply, from = recv_reply
          begin
            msg = Message.decode(reply)
          rescue DecodeError
            next # broken DNS message ignored
          end
          if s = @senders[[from,msg.id]]
            break
          else
            # unexpected DNS message ignored
          end
        end
        return msg, s.data
      end

      def close
        sock = @sock
        @sock = nil
        sock.close if sock
      end

      class Sender # :nodoc:
        def initialize(msg, data, sock)
          @msg = msg
          @data = data
          @sock = sock
        end
      end

      class UnconnectedUDP < Requester
        def initialize
          super()
          @sock = UDPSocket.new
          @sock.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC) if defined? Fcntl::F_SETFD
          DNS.bind_random_port(@sock)
        end

        def recv_reply
          reply, from = @sock.recvfrom(UDPSize)
          return reply, [from[3],from[1]]
        end

        def sender(msg, data, host, port=Port)
          service = [host, port]
          id = DNS.allocate_request_id(host, port)
          request = msg.encode
          request[0,2] = [id].pack('n')
          return @senders[[service, id]] =
            Sender.new(request, data, @sock, host, port)
        end

        def close
          super
          @senders.each_key {|service, id|
            DNS.free_request_id(service[0], service[1], id)
          }
        end

        class Sender < Requester::Sender
          def initialize(msg, data, sock, host, port)
            super(msg, data, sock)
            @host = host
            @port = port
          end
          attr_reader :data

          def send
            @sock.send(@msg, 0, @host, @port)
          end
        end
      end

      class ConnectedUDP < Requester
        def initialize(host, port=Port)
          super()
          @host = host
          @port = port
          @sock = UDPSocket.new(host.index(':') ? Socket::AF_INET6 : Socket::AF_INET)
          DNS.bind_random_port(@sock)
          @sock.connect(host, port)
          @sock.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC) if defined? Fcntl::F_SETFD
        end

        def recv_reply
          reply = @sock.recv(UDPSize)
          return reply, nil
        end

        def sender(msg, data, host=@host, port=@port)
          unless host == @host && port == @port
            raise RequestError.new("host/port don't match: #{host}:#{port}")
          end
          id = DNS.allocate_request_id(@host, @port)
          request = msg.encode
          request[0,2] = [id].pack('n')
          return @senders[[nil,id]] = Sender.new(request, data, @sock)
        end

        def close
          super
          @senders.each_key {|from, id|
            DNS.free_request_id(@host, @port, id)
          }
        end

        class Sender < Requester::Sender
          def send
            @sock.send(@msg, 0)
          end
          attr_reader :data
        end
      end

      class TCP < Requester
        def initialize(host, port=Port)
          super()
          @host = host
          @port = port
          @sock = TCPSocket.new(@host, @port)
          @sock.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC) if defined? Fcntl::F_SETFD
          @senders = {}
        end

        def recv_reply
          len = @sock.read(2).unpack('n')[0]
          reply = @sock.read(len)
          return reply, nil
        end

        def sender(msg, data, host=@host, port=@port)
          unless host == @host && port == @port
            raise RequestError.new("host/port don't match: #{host}:#{port}")
          end
          id = DNS.allocate_request_id(@host, @port)
          request = msg.encode
          request[0,2] = [request.length, id].pack('nn')
          return @senders[[nil,id]] = Sender.new(request, data, @sock)
        end

        class Sender < Requester::Sender
          def send
            @sock.print(@msg)
            @sock.flush
          end
          attr_reader :data
        end

        def close
          super
          @senders.each_key {|from,id|
            DNS.free_request_id(@host, @port, id)
          }
        end
      end

      class RequestError < StandardError
      end
    end

    class Config
      def initialize(config_info=nil)
        @mutex = Mutex.new
        @config_info = config_info
        @initialized = nil
      end

      def Config.parse_resolv_conf(filename)
        nameserver = []
        search = nil
        ndots = 1
        open(filename) {|f|
          f.each {|line|
            line.sub!(/[#;].*/, '')
            keyword, *args = line.split(/\s+/)
            args.each { |arg|
              arg.untaint
            }
            next unless keyword
            case keyword
            when 'nameserver'
              nameserver += args
            when 'domain'
              next if args.empty?
              search = [args[0]]
            when 'search'
              next if args.empty?
              search = args
            when 'options'
              args.each {|arg|
                case arg
                when /\Andots:(\d+)\z/
                  ndots = $1.to_i
                end
              }
            end
          }
        }
        return { :nameserver => nameserver, :search => search, :ndots => ndots }
      end

      def Config.default_config_hash(filename="/etc/resolv.conf")
        if File.exist? filename
          config_hash = Config.parse_resolv_conf(filename)
        else
          if /mswin32|cygwin|mingw|bccwin/ =~ RUBY_PLATFORM
            require 'win32/resolv'
            search, nameserver = Win32::Resolv.get_resolv_info
            config_hash = {}
            config_hash[:nameserver] = nameserver if nameserver
            config_hash[:search] = [search].flatten if search
          end
        end
        config_hash
      end

      def lazy_initialize
        @mutex.synchronize {
          unless @initialized
            @nameserver = []
            @search = nil
            @ndots = 1
            case @config_info
            when nil
              config_hash = Config.default_config_hash
            when String
              config_hash = Config.parse_resolv_conf(@config_info)
            when Hash
              config_hash = @config_info.dup
              if String === config_hash[:nameserver]
                config_hash[:nameserver] = [config_hash[:nameserver]]
              end
              if String === config_hash[:search]
                config_hash[:search] = [config_hash[:search]]
              end
            else
              raise ArgumentError.new("invalid resolv configuration: #{@config_info.inspect}")
            end
            @nameserver = config_hash[:nameserver] if config_hash.include? :nameserver
            @search = config_hash[:search] if config_hash.include? :search
            @ndots = config_hash[:ndots] if config_hash.include? :ndots

            @nameserver = ['0.0.0.0'] if @nameserver.empty?
            if @search
              @search = @search.map {|arg| Label.split(arg) }
            else
              hostname = Socket.gethostname
              if /\./ =~ hostname
                @search = [Label.split($')]
              else
                @search = [[]]
              end
            end

            if !@nameserver.kind_of?(Array) ||
               !@nameserver.all? {|ns| String === ns }
              raise ArgumentError.new("invalid nameserver config: #{@nameserver.inspect}")
            end

            if !@search.kind_of?(Array) ||
               !@search.all? {|ls| ls.all? {|l| Label::Str === l } }
              raise ArgumentError.new("invalid search config: #{@search.inspect}")
            end

            if !@ndots.kind_of?(Integer)
              raise ArgumentError.new("invalid ndots config: #{@ndots.inspect}")
            end

            @initialized = true
          end
        }
        self
      end

      def single?
        lazy_initialize
        if @nameserver.length == 1
          return @nameserver[0]
        else
          return nil
        end
      end

      def generate_candidates(name)
        candidates = nil
        name = Name.create(name)
        if name.absolute?
          candidates = [name]
        else
          if @ndots <= name.length - 1
            candidates = [Name.new(name.to_a)]
          else
            candidates = []
          end
          candidates.concat(@search.map {|domain| Name.new(name.to_a + domain)})
        end
        return candidates
      end

      InitialTimeout = 5

      def generate_timeouts
        ts = [InitialTimeout]
        ts << ts[-1] * 2 / @nameserver.length
        ts << ts[-1] * 2
        ts << ts[-1] * 2
        return ts
      end

      def resolv(name)
        candidates = generate_candidates(name)
        timeouts = generate_timeouts
        begin
          candidates.each {|candidate|
            begin
              timeouts.each {|tout|
                @nameserver.each {|nameserver|
                  begin
                    yield candidate, tout, nameserver
                  rescue ResolvTimeout
                  end
                }
              }
              raise ResolvError.new("DNS resolv timeout: #{name}")
            rescue NXDomain
            end
          }
        rescue ResolvError
        end
      end

      class NXDomain < ResolvError
      end

      class OtherResolvError < ResolvError
      end
    end

    module OpCode
      Query = 0
      IQuery = 1
      Status = 2
      Notify = 4
      Update = 5
    end

    module RCode
      NoError = 0
      FormErr = 1
      ServFail = 2
      NXDomain = 3
      NotImp = 4
      Refused = 5
      YXDomain = 6
      YXRRSet = 7
      NXRRSet = 8
      NotAuth = 9
      NotZone = 10
      BADVERS = 16
      BADSIG = 16
      BADKEY = 17
      BADTIME = 18
      BADMODE = 19
      BADNAME = 20
      BADALG = 21
    end

    class DecodeError < StandardError
    end

    class EncodeError < StandardError
    end

    module Label
      def self.split(arg)
        labels = []
        arg.scan(/[^\.]+/) {labels << Str.new($&)}
        return labels
      end

      class Str
        def initialize(string)
          @string = string
          @downcase = string.downcase
        end
        attr_reader :string, :downcase

        def to_s
          return @string
        end

        def inspect
          return "#<#{self.class} #{self.to_s}>"
        end

        def ==(other)
          return @downcase == other.downcase
        end

        def eql?(other)
          return self == other
        end

        def hash
          return @downcase.hash
        end
      end
    end

    class Name
      def self.create(arg)
        case arg
        when Name
          return arg
        when String
          return Name.new(Label.split(arg), /\.\z/ =~ arg ? true : false)
        else
          raise ArgumentError.new("cannot interpret as DNS name: #{arg.inspect}")
        end
      end

      def initialize(labels, absolute=true)
        @labels = labels
        @absolute = absolute
      end

      def inspect
        "#<#{self.class}: #{self.to_s}#{@absolute ? '.' : ''}>"
      end

      def absolute?
        return @absolute
      end

      def ==(other)
        return false unless Name === other
        return @labels == other.to_a && @absolute == other.absolute?
      end
      alias eql? ==

      # tests subdomain-of relation.
      #
      #   domain = Resolv::DNS::Name.create("y.z")
      #   p Resolv::DNS::Name.create("w.x.y.z").subdomain_of?(domain) #=> true
      #   p Resolv::DNS::Name.create("x.y.z").subdomain_of?(domain) #=> true
      #   p Resolv::DNS::Name.create("y.z").subdomain_of?(domain) #=> false
      #   p Resolv::DNS::Name.create("z").subdomain_of?(domain) #=> false
      #   p Resolv::DNS::Name.create("x.y.z.").subdomain_of?(domain) #=> false
      #   p Resolv::DNS::Name.create("w.z").subdomain_of?(domain) #=> false
      #
      def subdomain_of?(other)
        raise ArgumentError, "not a domain name: #{other.inspect}" unless Name === other
        return false if @absolute != other.absolute?
        other_len = other.length
        return false if @labels.length <= other_len
        return @labels[-other_len, other_len] == other.to_a
      end

      def hash
        return @labels.hash ^ @absolute.hash
      end

      def to_a
        return @labels
      end

      def length
        return @labels.length
      end

      def [](i)
        return @labels[i]
      end

      # returns the domain name as a string.
      #
      # The domain name doesn't have a trailing dot even if the name object is
      # absolute.
      #
      #   p Resolv::DNS::Name.create("x.y.z.").to_s #=> "x.y.z"
      #   p Resolv::DNS::Name.create("x.y.z").to_s #=> "x.y.z"
      #
      def to_s
        return @labels.join('.')
      end
    end

    class Message
      @@identifier = -1

      def initialize(id = (@@identifier += 1) & 0xffff)
        @id = id
        @qr = 0
        @opcode = 0
        @aa = 0
        @tc = 0
        @rd = 0 # recursion desired
        @ra = 0 # recursion available
        @rcode = 0
        @question = []
        @answer = []
        @authority = []
        @additional = []
      end

      attr_accessor :id, :qr, :opcode, :aa, :tc, :rd, :ra, :rcode
      attr_reader :question, :answer, :authority, :additional

      def ==(other)
        return @id == other.id &&
               @qr == other.qr &&
               @opcode == other.opcode &&
               @aa == other.aa &&
               @tc == other.tc &&
               @rd == other.rd &&
               @ra == other.ra &&
               @rcode == other.rcode &&
               @question == other.question &&
               @answer == other.answer &&
               @authority == other.authority &&
               @additional == other.additional
      end

      def add_question(name, typeclass)
        @question << [Name.create(name), typeclass]
      end

      def each_question
        @question.each {|name, typeclass|
          yield name, typeclass
        }
      end

      def add_answer(name, ttl, data)
        @answer << [Name.create(name), ttl, data]
      end

      def each_answer
        @answer.each {|name, ttl, data|
          yield name, ttl, data
        }
      end

      def add_authority(name, ttl, data)
        @authority << [Name.create(name), ttl, data]
      end

      def each_authority
        @authority.each {|name, ttl, data|
          yield name, ttl, data
        }
      end

      def add_additional(name, ttl, data)
        @additional << [Name.create(name), ttl, data]
      end

      def each_additional
        @additional.each {|name, ttl, data|
          yield name, ttl, data
        }
      end

      def each_resource
        each_answer {|name, ttl, data| yield name, ttl, data}
        each_authority {|name, ttl, data| yield name, ttl, data}
        each_additional {|name, ttl, data| yield name, ttl, data}
      end

      def encode
        return MessageEncoder.new {|msg|
          msg.put_pack('nnnnnn',
            @id,
            (@qr & 1) << 15 |
            (@opcode & 15) << 11 |
            (@aa & 1) << 10 |
            (@tc & 1) << 9 |
            (@rd & 1) << 8 |
            (@ra & 1) << 7 |
            (@rcode & 15),
            @question.length,
            @answer.length,
            @authority.length,
            @additional.length)
          @question.each {|q|
            name, typeclass = q
            msg.put_name(name)
            msg.put_pack('nn', typeclass::TypeValue, typeclass::ClassValue)
          }
          [@answer, @authority, @additional].each {|rr|
            rr.each {|r|
              name, ttl, data = r
              msg.put_name(name)
              msg.put_pack('nnN', data.class::TypeValue, data.class::ClassValue, ttl)
              msg.put_length16 {data.encode_rdata(msg)}
            }
          }
        }.to_s
      end

      class MessageEncoder
        def initialize
          @data = ''
          @names = {}
          yield self
        end

        def to_s
          return @data
        end

        def put_bytes(d)
          @data << d
        end

        def put_pack(template, *d)
          @data << d.pack(template)
        end

        def put_length16
          length_index = @data.length
          @data << "\0\0"
          data_start = @data.length
          yield
          data_end = @data.length
          @data[length_index, 2] = [data_end - data_start].pack("n")
        end

        def put_string(d)
          self.put_pack("C", d.length)
          @data << d
        end

        def put_string_list(ds)
          ds.each {|d|
            self.put_string(d)
          }
        end

        def put_name(d)
          put_labels(d.to_a)
        end

        def put_labels(d)
          d.each_index {|i|
            domain = d[i..-1]
            if idx = @names[domain]
              self.put_pack("n", 0xc000 | idx)
              return
            else
              @names[domain] = @data.length
              self.put_label(d[i])
            end
          }
          @data << "\0"
        end

        def put_label(d)
          self.put_string(d.string)
        end
      end

      def Message.decode(m)
        o = Message.new(0)
        MessageDecoder.new(m) {|msg|
          id, flag, qdcount, ancount, nscount, arcount =
            msg.get_unpack('nnnnnn')
          o.id = id
          o.qr = (flag >> 15) & 1
          o.opcode = (flag >> 11) & 15
          o.aa = (flag >> 10) & 1
          o.tc = (flag >> 9) & 1
          o.rd = (flag >> 8) & 1
          o.ra = (flag >> 7) & 1
          o.rcode = flag & 15
          (1..qdcount).each {
            name, typeclass = msg.get_question
            o.add_question(name, typeclass)
          }
          (1..ancount).each {
            name, ttl, data = msg.get_rr
            o.add_answer(name, ttl, data)
          }
          (1..nscount).each {
            name, ttl, data = msg.get_rr
            o.add_authority(name, ttl, data)
          }
          (1..arcount).each {
            name, ttl, data = msg.get_rr
            o.add_additional(name, ttl, data)
          }
        }
        return o
      end

      class MessageDecoder
        def initialize(data)
          @data = data
          @index = 0
          @limit = data.length
          yield self
        end

        def get_length16
          len, = self.get_unpack('n')
          save_limit = @limit
          @limit = @index + len
          d = yield(len)
          if @index < @limit
            raise DecodeError.new("junk exists")
          elsif @limit < @index
            raise DecodeError.new("limit exceeded")
          end
          @limit = save_limit
          return d
        end

        def get_bytes(len = @limit - @index)
          d = @data[@index, len]
          @index += len
          return d
        end

        def get_unpack(template)
          len = 0
          template.each_byte {|byte|
            case byte
            when ?c, ?C
              len += 1
            when ?n
              len += 2
            when ?N
              len += 4
            else
              raise StandardError.new("unsupported template: '#{byte.chr}' in '#{template}'")
            end
          }
          raise DecodeError.new("limit exceeded") if @limit < @index + len
          arr = @data.unpack("@#{@index}#{template}")
          @index += len
          return arr
        end

        def get_string
          len = @data[@index]
          raise DecodeError.new("limit exceeded") if @limit < @index + 1 + len
          d = @data[@index + 1, len]
          @index += 1 + len
          return d
        end

        def get_string_list
          strings = []
          while @index < @limit
            strings << self.get_string
          end
          strings
        end

        def get_name
          return Name.new(self.get_labels)
        end

        def get_labels(limit=nil)
          limit = @index if !limit || @index < limit
          d = []
          while true
            case @data[@index]
            when 0
              @index += 1
              return d
            when 192..255
              idx = self.get_unpack('n')[0] & 0x3fff
              if limit <= idx
                raise DecodeError.new("non-backward name pointer")
              end
              save_index = @index
              @index = idx
              d += self.get_labels(limit)
              @index = save_index
              return d
            else
              d << self.get_label
            end
          end
          return d
        end

        def get_label
          return Label::Str.new(self.get_string)
        end

        def get_question
          name = self.get_name
          type, klass = self.get_unpack("nn")
          return name, Resource.get_class(type, klass)
        end

        def get_rr
          name = self.get_name
          type, klass, ttl = self.get_unpack('nnN')
          typeclass = Resource.get_class(type, klass)
          return name, ttl, self.get_length16 {typeclass.decode_rdata(self)}
        end
      end
    end

    class Query
      def encode_rdata(msg)
        raise EncodeError.new("#{self.class} is query.") 
      end

      def self.decode_rdata(msg)
        raise DecodeError.new("#{self.class} is query.") 
      end
    end

    class Resource < Query
      ClassHash = {}

      def encode_rdata(msg)
        raise NotImplementedError.new
      end

      def self.decode_rdata(msg)
        raise NotImplementedError.new
      end

      def ==(other)
        return self.class == other.class &&
          self.instance_variables == other.instance_variables &&
          self.instance_variables.collect {|name| self.instance_eval name} ==
            other.instance_variables.collect {|name| other.instance_eval name}
      end

      def eql?(other)
        return self == other
      end

      def hash
        h = 0
        self.instance_variables.each {|name|
          h ^= self.instance_eval("#{name}.hash")
        }
        return h
      end

      def self.get_class(type_value, class_value)
        return ClassHash[[type_value, class_value]] ||
               Generic.create(type_value, class_value)
      end

      class Generic < Resource
        def initialize(data)
          @data = data
        end
        attr_reader :data

        def encode_rdata(msg)
          msg.put_bytes(data)
        end

        def self.decode_rdata(msg)
          return self.new(msg.get_bytes)
        end

        def self.create(type_value, class_value)
          c = Class.new(Generic)
          c.const_set(:TypeValue, type_value)
          c.const_set(:ClassValue, class_value)
          Generic.const_set("Type#{type_value}_Class#{class_value}", c)
          ClassHash[[type_value, class_value]] = c
          return c
        end
      end

      class DomainName < Resource
        def initialize(name)
          @name = name
        end
        attr_reader :name

        def encode_rdata(msg)
          msg.put_name(@name)
        end

        def self.decode_rdata(msg)
          return self.new(msg.get_name)
        end
      end

      # Standard (class generic) RRs
      ClassValue = nil

      class NS < DomainName
        TypeValue = 2
      end

      class CNAME < DomainName
        TypeValue = 5
      end

      class SOA < Resource
        TypeValue = 6

        def initialize(mname, rname, serial, refresh, retry_, expire, minimum)
          @mname = mname
          @rname = rname
          @serial = serial
          @refresh = refresh
          @retry = retry_
          @expire = expire
          @minimum = minimum
        end
        attr_reader :mname, :rname, :serial, :refresh, :retry, :expire, :minimum

        def encode_rdata(msg)
          msg.put_name(@mname)
          msg.put_name(@rname)
          msg.put_pack('NNNNN', @serial, @refresh, @retry, @expire, @minimum)
        end

        def self.decode_rdata(msg)
          mname = msg.get_name
          rname = msg.get_name
          serial, refresh, retry_, expire, minimum = msg.get_unpack('NNNNN')
          return self.new(
            mname, rname, serial, refresh, retry_, expire, minimum)
        end
      end

      class PTR < DomainName
        TypeValue = 12
      end

      class HINFO < Resource
        TypeValue = 13

        def initialize(cpu, os)
          @cpu = cpu
          @os = os
        end
        attr_reader :cpu, :os

        def encode_rdata(msg)
          msg.put_string(@cpu)
          msg.put_string(@os)
        end

        def self.decode_rdata(msg)
          cpu = msg.get_string
          os = msg.get_string
          return self.new(cpu, os)
        end
      end

      class MINFO < Resource
        TypeValue = 14

        def initialize(rmailbx, emailbx)
          @rmailbx = rmailbx
          @emailbx = emailbx
        end
        attr_reader :rmailbx, :emailbx

        def encode_rdata(msg)
          msg.put_name(@rmailbx)
          msg.put_name(@emailbx)
        end

        def self.decode_rdata(msg)
          rmailbx = msg.get_string
          emailbx = msg.get_string
          return self.new(rmailbx, emailbx)
        end
      end

      class MX < Resource
        TypeValue= 15

        def initialize(preference, exchange)
          @preference = preference
          @exchange = exchange
        end
        attr_reader :preference, :exchange

        def encode_rdata(msg)
          msg.put_pack('n', @preference)
          msg.put_name(@exchange)
        end

        def self.decode_rdata(msg)
          preference, = msg.get_unpack('n')
          exchange = msg.get_name
          return self.new(preference, exchange)
        end
      end

      class TXT < Resource
        TypeValue = 16

        def initialize(first_string, *rest_strings)
          @strings = [first_string, *rest_strings]
        end
        attr_reader :strings

        def data
          @strings[0]
        end

        def encode_rdata(msg)
          msg.put_string_list(@strings)
        end

        def self.decode_rdata(msg)
          strings = msg.get_string_list
          return self.new(*strings)
        end
      end

      class ANY < Query
        TypeValue = 255
      end

      ClassInsensitiveTypes = [
        NS, CNAME, SOA, PTR, HINFO, MINFO, MX, TXT, ANY
      ]

      # ARPA Internet specific RRs
      module IN
        ClassValue = 1

        ClassInsensitiveTypes.each {|s|
          c = Class.new(s)
          c.const_set(:TypeValue, s::TypeValue)
          c.const_set(:ClassValue, ClassValue)
          ClassHash[[s::TypeValue, ClassValue]] = c
          self.const_set(s.name.sub(/.*::/, ''), c)
        }

        class A < Resource
          ClassHash[[TypeValue = 1, ClassValue = ClassValue]] = self

          def initialize(address)
            @address = IPv4.create(address)
          end
          attr_reader :address

          def encode_rdata(msg)
            msg.put_bytes(@address.address)
          end

          def self.decode_rdata(msg)
            return self.new(IPv4.new(msg.get_bytes(4)))
          end
        end

        class WKS < Resource
          ClassHash[[TypeValue = 11, ClassValue = ClassValue]] = self

          def initialize(address, protocol, bitmap)
            @address = IPv4.create(address)
            @protocol = protocol
            @bitmap = bitmap
          end
          attr_reader :address, :protocol, :bitmap

          def encode_rdata(msg)
            msg.put_bytes(@address.address)
            msg.put_pack("n", @protocol)
            msg.put_bytes(@bitmap)
          end

          def self.decode_rdata(msg)
            address = IPv4.new(msg.get_bytes(4))
            protocol, = msg.get_unpack("n")
            bitmap = msg.get_bytes
            return self.new(address, protocol, bitmap)
          end
        end

        class AAAA < Resource
          ClassHash[[TypeValue = 28, ClassValue = ClassValue]] = self

          def initialize(address)
            @address = IPv6.create(address)
          end
          attr_reader :address

          def encode_rdata(msg)
            msg.put_bytes(@address.address)
          end

          def self.decode_rdata(msg)
            return self.new(IPv6.new(msg.get_bytes(16)))
          end
        end

        # SRV resource record defined in RFC 2782
        # 
        # These records identify the hostname and port that a service is
        # available at.
        # 
        # The format is:
        #   _Service._Proto.Name TTL Class SRV Priority Weight Port Target
        #
        # The fields specific to SRV are defined in RFC 2782 as meaning:
        # - +priority+ The priority of this target host.  A client MUST attempt
        #   to contact the target host with the lowest-numbered priority it can
        #   reach; target hosts with the same priority SHOULD be tried in an
        #   order defined by the weight field.  The range is 0-65535.  Note that
        #   it is not widely implemented and should be set to zero.
        # 
        # - +weight+ A server selection mechanism.  The weight field specifies
        #   a relative weight for entries with the same priority. Larger weights
        #   SHOULD be given a proportionately higher probability of being
        #   selected. The range of this number is 0-65535.  Domain administrators
        #   SHOULD use Weight 0 when there isn't any server selection to do, to
        #   make the RR easier to read for humans (less noisy). Note that it is
        #   not widely implemented and should be set to zero.
        #
        # - +port+  The port on this target host of this service.  The range is 0-
        #   65535.
        # 
        # - +target+ The domain name of the target host. A target of "." means
        #   that the service is decidedly not available at this domain.
        class SRV < Resource
          ClassHash[[TypeValue = 33, ClassValue = ClassValue]] = self

          # Create a SRV resource record.
          def initialize(priority, weight, port, target)
            @priority = priority.to_int
            @weight = weight.to_int
            @port = port.to_int
            @target = Name.create(target)
          end

          attr_reader :priority, :weight, :port, :target

          def encode_rdata(msg)
            msg.put_pack("n", @priority)
            msg.put_pack("n", @weight)
            msg.put_pack("n", @port)
            msg.put_name(@target)
          end

          def self.decode_rdata(msg)
            priority, = msg.get_unpack("n")
            weight,   = msg.get_unpack("n")
            port,     = msg.get_unpack("n")
            target    = msg.get_name
            return self.new(priority, weight, port, target)
          end
        end

      end
    end
  end

  class IPv4
    Regex = /\A(\d+)\.(\d+)\.(\d+)\.(\d+)\z/

    def self.create(arg)
      case arg
      when IPv4
        return arg
      when Regex
        if (0..255) === (a = $1.to_i) &&
           (0..255) === (b = $2.to_i) &&
           (0..255) === (c = $3.to_i) &&
           (0..255) === (d = $4.to_i)
          return self.new([a, b, c, d].pack("CCCC"))
        else
          raise ArgumentError.new("IPv4 address with invalid value: " + arg)
        end
      else
        raise ArgumentError.new("cannot interpret as IPv4 address: #{arg.inspect}")
      end
    end

    def initialize(address)
      unless address.kind_of?(String) && address.length == 4
        raise ArgumentError.new('IPv4 address must be 4 bytes')
      end
      @address = address
    end
    attr_reader :address

    def to_s
      return sprintf("%d.%d.%d.%d", *@address.unpack("CCCC"))
    end

    def inspect
      return "#<#{self.class} #{self.to_s}>"
    end

    def to_name
      return DNS::Name.create(
        '%d.%d.%d.%d.in-addr.arpa.' % @address.unpack('CCCC').reverse)
    end

    def ==(other)
      return @address == other.address
    end

    def eql?(other)
      return self == other
    end

    def hash
      return @address.hash
    end
  end

  class IPv6
    Regex_8Hex = /\A
      (?:[0-9A-Fa-f]{1,4}:){7}
         [0-9A-Fa-f]{1,4}
      \z/x

    Regex_CompressedHex = /\A
      ((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?) ::
      ((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?)
      \z/x

    Regex_6Hex4Dec = /\A
      ((?:[0-9A-Fa-f]{1,4}:){6,6})
      (\d+)\.(\d+)\.(\d+)\.(\d+)
      \z/x

    Regex_CompressedHex4Dec = /\A
      ((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?) ::
      ((?:[0-9A-Fa-f]{1,4}:)*)
      (\d+)\.(\d+)\.(\d+)\.(\d+)
      \z/x

    Regex = /
      (?:#{Regex_8Hex}) |
      (?:#{Regex_CompressedHex}) |
      (?:#{Regex_6Hex4Dec}) |
      (?:#{Regex_CompressedHex4Dec})/x

    def self.create(arg)
      case arg
      when IPv6
        return arg
      when String
        address = ''
        if Regex_8Hex =~ arg
          arg.scan(/[0-9A-Fa-f]+/) {|hex| address << [hex.hex].pack('n')}
        elsif Regex_CompressedHex =~ arg
          prefix = $1
          suffix = $2
          a1 = ''
          a2 = ''
          prefix.scan(/[0-9A-Fa-f]+/) {|hex| a1 << [hex.hex].pack('n')}
          suffix.scan(/[0-9A-Fa-f]+/) {|hex| a2 << [hex.hex].pack('n')}
          omitlen = 16 - a1.length - a2.length
          address << a1 << "\0" * omitlen << a2
        elsif Regex_6Hex4Dec =~ arg
          prefix, a, b, c, d = $1, $2.to_i, $3.to_i, $4.to_i, $5.to_i
          if (0..255) === a && (0..255) === b && (0..255) === c && (0..255) === d
            prefix.scan(/[0-9A-Fa-f]+/) {|hex| address << [hex.hex].pack('n')}
            address << [a, b, c, d].pack('CCCC')
          else
            raise ArgumentError.new("not numeric IPv6 address: " + arg)
          end
        elsif Regex_CompressedHex4Dec =~ arg
          prefix, suffix, a, b, c, d = $1, $2, $3.to_i, $4.to_i, $5.to_i, $6.to_i
          if (0..255) === a && (0..255) === b && (0..255) === c && (0..255) === d
            a1 = ''
            a2 = ''
            prefix.scan(/[0-9A-Fa-f]+/) {|hex| a1 << [hex.hex].pack('n')}
            suffix.scan(/[0-9A-Fa-f]+/) {|hex| a2 << [hex.hex].pack('n')}
            omitlen = 12 - a1.length - a2.length
            address << a1 << "\0" * omitlen << a2 << [a, b, c, d].pack('CCCC')
          else
            raise ArgumentError.new("not numeric IPv6 address: " + arg)
          end
        else
          raise ArgumentError.new("not numeric IPv6 address: " + arg)
        end
        return IPv6.new(address)
      else
        raise ArgumentError.new("cannot interpret as IPv6 address: #{arg.inspect}")
      end
    end

    def initialize(address)
      unless address.kind_of?(String) && address.length == 16
        raise ArgumentError.new('IPv6 address must be 16 bytes')
      end
      @address = address
    end
    attr_reader :address

    def to_s
      address = sprintf("%X:%X:%X:%X:%X:%X:%X:%X", *@address.unpack("nnnnnnnn"))
      unless address.sub!(/(^|:)0(:0)+(:|$)/, '::')
        address.sub!(/(^|:)0(:|$)/, '::')
      end
      return address
    end

    def inspect
      return "#<#{self.class} #{self.to_s}>"
    end

    def to_name
      # ip6.arpa should be searched too. [RFC3152]
      return DNS::Name.new(
        @address.unpack("H32")[0].split(//).reverse + ['ip6', 'int'])
    end

    def ==(other)
      return @address == other.address
    end

    def eql?(other)
      return self == other
    end

    def hash
      return @address.hash
    end
  end

  DefaultResolver = self.new
  AddressRegex = /(?:#{IPv4::Regex})|(?:#{IPv6::Regex})/
end
