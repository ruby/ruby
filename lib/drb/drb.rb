=begin
= distributed Ruby --- dRuby 2.0.4
 	Copyright (c) 1999-2003 Masatoshi SEKI 
        You can redistribute it and/or modify it under the same terms as Ruby.
=end

require 'socket'
require 'thread'
require 'fcntl'

module DRb
  class DRbError < RuntimeError; end
  class DRbConnError < DRbError; end

  class DRbIdConv
    def to_obj(ref)
      ObjectSpace._id2ref(ref)
    end
    
    def to_id(obj)
      obj.nil? ? nil : obj.__id__
    end
  end

  module DRbUndumped 
    def _dump(dummy)
      raise TypeError, 'can\'t dump'
    end
  end

  class DRbServerNotFound < DRbError; end
  class DRbBadURI < DRbError; end
  class DRbBadScheme < DRbError; end

  class DRbUnknownError < DRbError
    def initialize(unknown)
      @unknown = unknown
      super(unknown.name)
    end
    attr_reader :unknown

    def self._load(s)
      Marshal::load(s)
    end
    
    def _dump(lv)
      Marshal::dump(@unknown)
    end
  end

  class DRbUnknown
    def initialize(err, buf)
      case err
      when /uninitialized constant (\S+)/
	@name = $1
      when /undefined class\/module (\S+)/
	@name = $1
      else
	@name = nil
      end
      @buf = buf
    end
    attr_reader :name, :buf

    def self._load(s)
      begin
	Marshal::load(s)
      rescue NameError, ArgumentError
	DRbUnknown.new($!, s)
      end
    end

    def _dump(lv)
      @buf
    end

    def reload
      self.class._load(@buf)
    end

    def exception
      DRbUnknownError.new(self)
    end
  end

  class DRbMessage
    def initialize(config)
      @load_limit = config[:load_limit]
      @argc_limit = config[:argc_limit]
    end

    def dump(obj)
      obj = DRbObject.new(obj) if obj.kind_of? DRbUndumped
      begin
	str = Marshal::dump(obj)
      rescue
	str = Marshal::dump(DRbObject.new(obj))
      end
      [str.size].pack('N') + str
    end

    def load(soc)
      sz = soc.read(4)	# sizeof (N)
      raise(DRbConnError, 'connection closed') if sz.nil?
      raise(DRbConnError, 'premature header') if sz.size < 4
      sz = sz.unpack('N')[0]
      raise(DRbConnError, "too large packet #{sz}") if @load_limit < sz
      str = soc.read(sz)
      raise(DRbConnError, 'connection closed') if sz.nil?
      raise(DRbConnError, 'premature marshal format(can\'t read)') if str.size < sz
      begin
	Marshal::load(str)
      rescue NameError, ArgumentError
	DRbUnknown.new($!, str)
      end
    end

    def send_request(stream, ref, msg_id, arg, b)
      ary = []
      ary.push(dump(ref.__drbref))
      ary.push(dump(msg_id.id2name))
      ary.push(dump(arg.length))
      arg.each do |e|
	ary.push(dump(e))
      end
      ary.push(dump(b))
      stream.write(ary.join(''))
    end
    
    def recv_request(stream)
      ref = load(stream)
      ro = DRb.to_obj(ref)
      msg = load(stream)
      argc = load(stream)
      raise ArgumentError, 'too many arguments' if @argc_limit < argc
      argv = Array.new(argc, nil)
      argc.times do |n|
	argv[n] = load(stream)
      end
      block = load(stream)
      return ro, msg, argv, block
    end

    def send_reply(stream, succ, result)
      stream.write(dump(succ) + dump(result))
    end

    def recv_reply(stream)
      succ = load(stream)
      result = load(stream)
      [succ, result]
    end
  end

  module DRbProtocol
    module_function
    def add_protocol(prot)
      @protocol.push(prot)
    end

    module_function
    def open(uri, config, first=true) 
      @protocol.each do |prot|
	begin
	  return prot.open(uri, config)
	rescue DRbBadScheme
	rescue DRbConnError
	  raise($!)
	rescue
	  raise(DRbConnError, "#{uri} - #{$!.inspect}")
	end
      end
      if first && (config[:auto_load] != false)
	auto_load(uri, config)
	return open(uri, config, false)
      end
      raise DRbBadURI, 'can\'t parse uri:' + uri
    end

    module_function
    def open_server(uri, config, first=true)
      @protocol.each do |prot|
	begin
	  return prot.open_server(uri, config)
	rescue DRbBadScheme
	end
      end
      if first && (config[:auto_load] != false)
	auto_load(uri, config)
	return open_server(uri, config, false)
      end
      raise DRbBadURI, 'can\'t parse uri:' + uri
    end

    module_function
    def uri_option(uri, config, first=true)
      @protocol.each do |prot|
	begin
	  uri, opt = prot.uri_option(uri, config)
	  # opt = nil if opt == ''
	  return uri, opt
	rescue DRbBadScheme
	end
      end
      if first && (config[:auto_load] != false)
	auto_load(uri, config)
        return uri_option(uri, config, false)
      end
      raise DRbBadURI, 'can\'t parse uri:' + uri
    end

    module_function
    def auto_load(uri, config)
      if uri =~ /^drb([a-z0-9]+):/
	require("drb/#{$1}") rescue nil
      end
    end
  end

  class DRbTCPSocket
    private
    def self.parse_uri(uri)
      if uri =~ /^druby:\/\/(.*?):(\d+)(\?(.*))?$/
	host = $1
	port = $2.to_i
	option = $4
	[host, port, option]
      else
	raise(DRbBadScheme, uri) unless uri =~ /^druby:/
	raise(DRbBadURI, 'can\'t parse uri:' + uri)
      end
    end

    public
    def self.open(uri, config)
      host, port, option = parse_uri(uri)
      host.untaint
      port.untaint
      soc = TCPSocket.open(host, port)
      self.new(uri, soc, config)
    end

    def self.open_server(uri, config)
      uri = 'druby://:0' unless uri
      host, port, opt = parse_uri(uri)
      if host.size == 0
	soc = TCPServer.open(port)
	host = Socket.gethostname
      else
	soc = TCPServer.open(host, port)
      end
      port = soc.addr[1] if port == 0
      uri = "druby://#{host}:#{port}"
      self.new(uri, soc, config)
    end

    def self.uri_option(uri, config)
      host, port, option = parse_uri(uri)
      return "druby://#{host}:#{port}", option
    end

    def initialize(uri, soc, config={})
      @uri = uri
      @socket = soc
      @config = config
      @acl = config[:tcp_acl]
      @msg = DRbMessage.new(config)
      set_sockopt(@socket)
    end
    attr_reader :uri

    def peeraddr
      @socket.peeraddr
    end
    
    def stream; @socket; end

    def send_request(ref, msg_id, arg, b)
      @msg.send_request(stream, ref, msg_id, arg, b)
    end
    
    def recv_request
      @msg.recv_request(stream)
    end

    def send_reply(succ, result)
      @msg.send_reply(stream, succ, result)
    end

    def recv_reply
      @msg.recv_reply(stream)
    end

    public
    def close
      if @socket
	@socket.close
	@socket = nil
      end
    end
    
    def accept
      while true
	s = @socket.accept
	break if (@acl ? @acl.allow_socket?(s) : true) 
	s.close
      end
      self.class.new(nil, s, @config)
    end

    def alive?
      return false unless @socket
      if IO.select([@socket], nil, nil, 0)
	close
	return false
      end
      true
    end

    def set_sockopt(soc)
      soc.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      soc.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK) if defined? Fcntl::O_NONBLOCK
      soc.fcntl(Fcntl::F_SETFL, Fcntl::FD_CLOEXEC) if defined? Fcntl::FD_CLOEXEC
    end
  end

  module DRbProtocol
    @protocol = [DRbTCPSocket] # default
  end

  class DRbURIOption
    def initialize(option)
      @option = option.to_s
    end
    attr :option
    def to_s; @option; end
    
    def ==(other)
      return false unless DRbURIOption === other
      @option == other.option
    end
    
    def hash
      @option.hash
    end
    
    alias eql? ==
  end

  class DRbObject
    def self._load(s)
      uri, ref = Marshal.load(s)
      if DRb.here?(uri)
	return DRb.to_obj(ref)
      end

      it = self.new(nil)
      it.reinit(uri, ref)
      it
    end

    def self.new_with_uri(uri)
      self.new(nil, uri)
    end

    def _dump(lv)
      Marshal.dump([@uri, @ref])
    end

    def initialize(obj, uri=nil)
      @uri = nil
      @ref = nil
      if obj.nil?
	return if uri.nil?
	@uri, option = DRbProtocol.uri_option(uri, DRb.config)
	@ref = DRbURIOption.new(option) unless option.nil?
      else
	@uri = uri ? uri : (DRb.uri rescue nil)
	@ref = obj ? DRb.to_id(obj) : nil
      end
    end

    def reinit(uri, ref)
      @uri = uri
      @ref = ref
    end

    def __drburi
      @uri
    end

    def __drbref
      @ref
    end

    undef :to_s
    undef :to_a
    undef :respond_to?

    def method_missing(msg_id, *a, &b)
      if DRb.here?(@uri)
	obj = DRb.to_obj(@ref)
	DRb.current_server.check_insecure_method(obj, msg_id)
	return obj.__send__(msg_id, *a, &b) 
      end

      succ, result = DRbConn.open(@uri) do |conn|
	conn.send_message(self, msg_id, a, b)
      end
      return result if succ
      unless DRbUnknown === result
	prefix = "(#{@uri}) "
	bt = []
	result.backtrace.each do |x|
	  break if /`__send__'$/ =~ x 
	  if /^\(druby:\/\// =~ x
	    bt.push(x)
	  else
	    bt.push(prefix + x)
	  end
	end
	raise result, result.message, bt + caller
      else
	raise result
      end
    end
  end

  class DRbConn
    POOL_SIZE = 16
    @mutex = Mutex.new
    @pool = []

    def self.open(remote_uri)
      begin
	conn = nil

	@mutex.synchronize do
	  #FIXME
	  new_pool = []
	  @pool.each do |c|
	    if conn.nil? and c.uri == remote_uri
	      conn = c if c.alive?
	    else
	      new_pool.push c
	    end
	  end
	  @pool = new_pool
	end

	conn = self.new(remote_uri) unless conn
	succ, result = yield(conn)
	return succ, result

      ensure
	@mutex.synchronize do
	  if @pool.size > POOL_SIZE or ! succ
	    conn.close if conn
	  else
	    @pool.unshift(conn)
	  end
	end
      end
    end

    def initialize(remote_uri)
      @uri = remote_uri
      @protocol = DRbProtocol.open(remote_uri, DRb.config)
    end
    attr_reader :uri

    def send_message(ref, msg_id, arg, block)
      @protocol.send_request(ref, msg_id, arg, block)
      @protocol.recv_reply
    end

    def close
      @protocol.close
      @protocol = nil
    end

    def alive?
      @protocol.alive?
    end
  end

  class DRbServer
    @@acl = nil
    @@idconv = DRbIdConv.new
    @@secondary_server = nil
    @@argc_limit = 256
    @@load_limit = 256 * 102400
    @@verbose = false

    def self.default_argc_limit(argc)
      @@argc_limit = argc
    end

    def self.default_load_limit(sz)
      @@load_limit = sz
    end

    def self.default_acl(acl)
      @@acl = acl
    end

    def self.default_id_conv(idconv)
      @@idconv = idconv
    end

    def self.verbose=(on)
      @@verbose = on
    end
    
    def self.verbose
      @@verbose
    end

    def self.make_config(hash={})
      default_config = { 
	:idconv => @@idconv,
	:verbose => @@verbose,
	:tcp_acl => @@acl,
	:load_limit => @@load_limit,
	:argc_limit => @@argc_limit
      }
      default_config.update(hash)
    end

    def initialize(uri=nil, front=nil, config_or_acl=nil)
      if Hash === config_or_acl
	config = config_or_acl.dup
      else
	acl = config_or_acl || @@acl
	config = {
	  :tcp_acl => acl
	}
      end

      @config = self.class.make_config(config)

      @protocol = DRbProtocol.open_server(uri, @config)
      @uri = @protocol.uri

      @front = front
      @idconv = @config[:idconv]

      @grp = ThreadGroup.new
      @thread = run

      Thread.exclusive do
	DRb.primary_server = self unless DRb.primary_server
      end
    end
    attr_reader :uri, :thread, :front
    attr_reader :config

    def verbose=(v); @config[:verbose]=v; end
    def verbose; @config[:verbose]; end

    def alive?
      @thread.alive?
    end

    def stop_service
      @thread.kill
    end

    def to_obj(ref)
      return front if ref.nil?
      return front[ref.to_s] if DRbURIOption === ref
      @idconv.to_obj(ref)
    end

    def to_id(obj)
      return nil if obj.__id__ == front.__id__
      @idconv.to_id(obj)
    end

    private
    def kill_sub_thread
      Thread.new do
	grp = ThreadGroup.new
	grp.add(Thread.current)
	list = @grp.list
	while list.size > 0
	  list.each do |th|
	    th.kill if th.alive?
	  end
	  list = @grp.list
	end
      end
    end

    def run
      Thread.start do
	begin
	  while true
	    main_loop
	  end
	ensure
	  @protocol.close if @protocol
	  kill_sub_thread
	end
      end
    end

    INSECURE_METHOD = [
      :__send__
    ]
    def insecure_method?(msg_id)
      INSECURE_METHOD.include?(msg_id)
    end

    def any_to_s(obj)
      obj.to_s rescue sprintf("#<%s:0x%lx>", obj.class, obj.__id__)      
    end

    def check_insecure_method(obj, msg_id)
      return true if Proc === obj && msg_id == :__drb_yield
      raise(ArgumentError, "#{any_to_s(msg_id)} is not a symbol") unless Symbol == msg_id.class
      raise(SecurityError, "insecure method `#{msg_id}'") if insecure_method?(msg_id)
      unless obj.respond_to?(msg_id)
	desc = any_to_s(obj)
	if desc.nil? || desc[0] == '#'
	  desc << ":#{obj.class}"
	end
	
	if obj.private_methods.include?(msg_id.to_s)
	  raise NameError, "private method `#{msg_id}' called for #{desc}"
	else
	  raise NameError, "undefined method `#{msg_id}' called for #{desc}"
	end
      end
      true
    end
    public :check_insecure_method

    class InvokeMethod
      def initialize(drb_server, client)
	@drb_server = drb_server
	@client = client
      end

      def perform
	@result = nil
	@succ = false
	setup_message
        if @block
          @result = perform_with_block
        else
          @result = perform_without_block
        end
	@succ = true
	return @succ, @result
      rescue StandardError, ScriptError, Interrupt
	@result = $!
	return @succ, @result
      end

      private
      def init_with_client
	obj, msg, argv, block = @client.recv_request
        @obj = obj
        @msg_id = msg.intern
        @argv = argv
        @block = block
      end
      
      def check_insecure_method
        @drb_server.check_insecure_method(@obj, @msg_id)
      end

      def setup_message
	init_with_client
	check_insecure_method
      end
      
      def perform_without_block
	if Proc === @obj && @msg_id == :__drb_yield
          if @argv.size == 1
	    ary = @argv
	  else
	    ary = [@argv]
	  end
	  ary.collect(&@obj)[0]
	else
	  @obj.__send__(@msg_id, *@argv)
	end
      end

    end

    if RUBY_VERSION >= '1.8'
      require 'drb/invokemethod'
      class InvokeMethod
        include InvokeMethod18Mixin
      end
    else
      require 'drb/invokemethod16'
      class InvokeMethod
        include InvokeMethod16Mixin
      end
    end

    def main_loop
      Thread.start(@protocol.accept) do |client|
	@grp.add Thread.current
	Thread.current['DRb'] = { 'client' => client ,
	                          'server' => self }
	loop do
	  begin
	    succ = false
	    invoke_method = InvokeMethod.new(self, client)
	    succ, result = invoke_method.perform
	    if !succ && verbose
	      p result
	      result.backtrace.each do |x|
		puts x
	      end
	    end
	    client.send_reply(succ, result) rescue nil
	  ensure
	    unless succ
	      client.close
	      return
	    end
	  end
	end
      end
    end
  end

  @primary_server = nil

  def start_service(uri=nil, front=nil, config=nil)
    @primary_server = DRbServer.new(uri, front, config)
  end
  module_function :start_service

  attr_accessor :primary_server
  module_function :primary_server=, :primary_server

  def current_server
    drb = Thread.current['DRb'] 
    server = (drb && drb['server']) ? drb['server'] : @primary_server 
    raise DRbServerNotFound unless server
    return server
  end
  module_function :current_server

  def stop_service
    @primary_server.stop_service if @primary_server
    @primary_server = nil
  end
  module_function :stop_service

  def uri
    current_server.uri
  end
  module_function :uri

  def here?(uri)
    (current_server.uri rescue nil) == uri
  end
  module_function :here?

  def config
    current_server.config
  rescue
    DRbServer.make_config
  end
  module_function :config
  
  def front
    current_server.front
  end
  module_function :front

  def to_obj(ref)
    current_server.to_obj(ref)
  end
  def to_id(obj)
    current_server.to_id(obj)
  end
  module_function :to_id
  module_function :to_obj

  def thread
    @primary_server ? @primary_server.thread : nil
  end
  module_function :thread

  def install_id_conv(idconv)
    DRbServer.default_id_conv(idconv)
  end
  module_function :install_id_conv

  def install_acl(acl)
    DRbServer.default_acl(acl)
  end
  module_function :install_acl
end

DRbObject = DRb::DRbObject
DRbUndumped = DRb::DRbUndumped
DRbIdConv = DRb::DRbIdConv
