#
# $Id$
#
# Copyright (c) 2001 akira yamada <akira@ruby-lang.org>
# You can redistribute it and/or modify it under the same term as Ruby.
#

require 'uri/common'

module URI

=begin

== URI::Generic

=== Super Class

Object

=end

  class Generic
    include REGEXP

=begin

=== Class Methods

--- URI::Generic::default_port

=end
    DEFAULT_PORT = nil

    def self.default_port
      self::DEFAULT_PORT
    end

    def default_port
      self.type.default_port
    end

=begin
--- URI::Generic::component
=end
    COMPONENT = [
      :scheme, 
      :userinfo, :host, :port, :registry, 
      :path, :opaque, 
      :query, 
      :fragment
    ].freeze

    def self.component
      self::COMPONENT
    end

=begin

--- URI::Generic::build2
    At first, try to create a new URI::Generic object using
    URI::Generic::build. But, if you get a exception
    URI::InvalidComponentError, then re-try to create an object with
    escaped components.

--- URI::Generic::build
    Create a new URI::Generic object from components of URI::Generic
    with check.  It is scheme, userinfo, host, port, registry, path,
    opaque, query and fragment. It provided by an Array of a Hash.

--- URI::Generic::new
    Create new URI::Generic object from ``generic'' components with no
    check.

=end
    def self.build2(args)
      begin
	return self.build(args)
      rescue InvalidComponentError
	if args.kind_of?(Array)
	  return self.build(args.collect{|x| 
			      if x
				URI.escape(x)
			      else
				x
			      end
			    })
	elsif args.kind_of?(Hash)
	  tmp = {}
	  args.each do |key, value|
	    tmp[key] = if value
			 URI.escape(value)
		       else
			 value
		       end
	  end
	  return self.build(tmp)
	end
      end
    end

    def self.build(args)
      if args.kind_of?(Array) &&
	  args.size == ::URI::Generic::COMPONENT.size
	tmp = args
      elsif args.kind_of?(Hash)
	tmp = ::URI::Generic::COMPONENT.collect do |c|
	  if args.include?(c)
	    args[c]
	  else
	    nil
	  end
	end
      else
	raise ArgumentError, 
	  "expected Array of or Hash of compornents of #{self.type} (#{self.type.component.join(', ')})"
      end

      tmp << true
      return self.new(*tmp)
    end

    def initialize(scheme, 
		   userinfo, host, port, registry, 
		   path, opaque, 
		   query, 
		   fragment,
		   arg_check = false)
      @scheme = nil
      @user = nil
      @password = nil
      @host = nil
      @port = nil
      @path = nil
      @query = nil
      @opaque = nil
      @registry = nil
      @fragment = nil

      if arg_check
	self.scheme = scheme
	self.userinfo = userinfo
	self.host = host
	self.port = port
	self.path = path
	self.query = query
	self.opaque = opaque
	self.registry = registry
	self.fragment = fragment
      else
	self.set_scheme(scheme)
	self.set_userinfo(userinfo)
	self.set_host(host)
	self.set_port(port)
	self.set_path(path)
	self.set_query(query)
	self.set_opaque(opaque)
	self.set_registry(registry)
	self.set_fragment(fragment)
      end
      
      @scheme.freeze if @scheme
      self.set_path('') if !@path && !@opaque # (see RFC2396 Section 5.2)
      self.set_port(self.default_port) if self.default_port && !@port
    end
    attr_reader :scheme
    attr_reader :host
    attr_reader :port
    attr_reader :registry
    attr_reader :path
    attr_reader :query
    attr_reader :opaque
    attr_reader :fragment

=begin

=== Instance Methods

=end

=begin

--- URI::Generic#component

=end
    def component
      self.type.component
    end

    # set_XXX method sets value to @XXX instance variable with no check, 
    # so be careful if you use these methods. or, you use these method 
    # with check_XXX method, or you use XXX= methods.

=begin

--- URI::Generic#scheme

--- URI::Generic#scheme=(v)

=end
    #
    # methods for scheme
    #
    def check_scheme(v)
      if v && SCHEME !~ v
	raise InvalidComponentError,
	  "bad component(expected scheme component): #{v}"
      end

      return true
    end
    private :check_scheme

    def set_scheme(v)
      @scheme = v
    end
    protected :set_scheme

    def scheme=(v)
      check_scheme(v)
      set_scheme(v)
    end

=begin

--- URI::Generic#userinfo

--- URI::Generic#userinfo=(v)

--- URI::Generic#user

--- URI::Generic#user=(v)

--- URI::Generic#password

--- URI::Generic#password=(v)

=end
    #
    # methods for userinfo
    #
    def check_userinfo(user, password = nil)
      if (user || password) &&
	  (@registry || @opaque)
	raise InvalidURIError, 
	  "can not set userinfo with registry or opaque"
      end

      if !password
	user, password = split_userinfo(user)
      end
      check_user(user)
      check_password(password)

      return true
    end
    private :check_userinfo

    def check_user(v)
      return v unless v

      if USERINFO !~ v
	raise InvalidComponentError,
	  "bad component(expected userinfo component or user component): #{v}"
      end

      return true
    end
    private :check_user

    def check_password(v)
      return v unless v

      if !@password
	raise InvalidURIError,
	  "password component depends user component"
      end

      if USERINFO !~ v
	raise InvalidComponentError,
	  "bad component(expected user component): #{v}"
      end

      return true
    end
    private :check_password

    def userinfo=(user, password = nil)
      check_userinfo(user, password)
      set_userinfo(user, password)
    end

    def user=(user)
      check_user(user)
      set_user(user)
    end

    def password=(password)
      check_password(password)
      set_password(password)
    end

    def set_userinfo(user, password = nil)
      if !password
	user, password = split_userinfo(user)
      end
      @user     = user
      @password = password
    end
    protected :set_userinfo

    def set_user(v)
      set_userinfo(v, @password)
    end
    protected :set_user

    def set_password(v)
      set_userinfo(@user, v)
    end
    protected :set_password

    def split_userinfo(ui)
      return nil, nil unless ui
      tmp = ui.index(':')
      if tmp
	user     = ui[0..tmp - 1]
	password = ui[tmp + 1..-1]
      else
	user     = ui
	password = nil
      end

      return user, password
    end
    private :split_userinfo

    def escape_userpass(v)
      v = URI.escape(v, /[@:\/]/o) # RFC 1738 section 3.1 #/
    end
    private :escape_userpass

    def userinfo
      if !@password
	@user
      else
	@user + ':' + @password
      end
    end

    def user
      @user
    end

    def password
      @password
    end

=begin

--- URI::Generic#host

--- URI::Generic#host=(v)

=end
    #
    # methods for host
    #

    def check_host(v)
      return v unless v

      if @registry || @opaque
	raise InvalidURIError, 
	  "can not set host with registry or opaque"
      elsif HOST !~ v
	raise InvalidComponentError,
	  "bad component(expected host component): #{v}"
      end

      return true
    end
    private :check_host

    def set_host(v)
      @host = v
    end
    protected :set_host

    def host=(v)
      check_host(v)
      set_host(v)
    end

=begin

--- URI::Generic#port

--- URI::Generic#port=(v)

=end
    #
    # methods for port
    #

    def check_port(v)
      return v unless v

      if @registry || @opaque
	raise InvalidURIError, 
	  "can not set port with registry or opaque"
      elsif !v.kind_of?(Fixnum) && PORT !~ v
	raise InvalidComponentError,
	  "bad component(expected port component): #{v}"
      end

      return true
    end
    private :check_port

    def set_port(v)
      v = v.to_i if v && !v.kind_of?(Fixnum)
      @port = v
    end
    protected :set_port

    def port=(v)
      check_port(v)
      set_port(v)
    end

=begin

--- URI::Generic#registry

--- URI::Generic#registry=(v)

=end
    #
    # methods for registry
    #

    def check_registry(v)
      return v unless v

      # raise if both server and registry are not nil, because:
      # authority     = server | reg_name
      # server        = [ [ userinfo "@" ] hostport ]
      if @host || @port || @user # userinfo = @user + ':' + @password
	raise InvalidURIError, 
	  "can not set registry with host, port, or userinfo"
      elsif v && REGISTRY !~ v
	raise InvalidComponentError,
	  "bad component(expected registry component): #{v}"
      end

      return true
    end
    private :check_registry

    def set_registry(v)
      @registry = v
    end
    protected :set_registry

    def registry=(v)
      check_registry(v)
      set_registry(v)
    end

=begin

--- URI::Generic#path

--- URI::Generic#path=(v)

=end
    #
    # methods for path
    #

    def check_path(v)
      # raise if both hier and opaque are not nil, because:
      # absoluteURI   = scheme ":" ( hier_part | opaque_part )
      # hier_part     = ( net_path | abs_path ) [ "?" query ]
      if v && @opaque
	raise InvalidURIError, 
	  "path conflicts with opaque"
      end

      if @scheme
	if v && v != '' && ABS_PATH !~ v
	  raise InvalidComponentError, 
	    "bad component(expected absolute path component): #{v}"
	end
      else
	if v && v != '' && ABS_PATH !~ v && REL_PATH !~ v
	  raise InvalidComponentError, 
	    "bad component(expected relative path component): #{@path}"
	end
      end

      return true
    end
    private :check_path

    def set_path(v)
      @path = v
    end
    protected :set_path

    def path=(v)
      check_path(v)
      set_path(v)
    end

=begin

--- URI::Generic#query

--- URI::Generic#query=(v)

=end
    #
    # methods for query
    #

    def check_query(v)
      return v unless v

      # raise if both hier and opaque are not nil, because:
      # absoluteURI   = scheme ":" ( hier_part | opaque_part )
      # hier_part     = ( net_path | abs_path ) [ "?" query ]
      if @opaque
	raise InvalidURIError, 
	  "query conflicts with opaque"
      end

      if v && v != '' && QUERY !~ v
	  raise InvalidComponentError, 
	    "bad component(expected query component): #{v}"
	end

      return true
    end
    private :check_query

    def set_query(v)
      @query = v
    end
    protected :set_query

    def query=(v)
      check_query(v)
      set_query(v)
    end

=begin

--- URI::Generic#opaque

--- URI::Generic#opaque=(v)

=end
    #
    # methods for opaque
    #

    def check_opaque(v)
      return v unless v

      # raise if both hier and opaque are not nil, because:
      # absoluteURI   = scheme ":" ( hier_part | opaque_part )
      # hier_part     = ( net_path | abs_path ) [ "?" query ]
      if @host || @port || @usr || @path  # userinfo = @user + ':' + @password
	raise InvalidURIError, 
	  "can not set opaque with host, port, userinfo or path"
      elsif v && OPAQUE !~ v
	raise InvalidComponentError,
	  "bad component(expected opaque component): #{v}"
      end

      return true
    end
    private :check_opaque

    def set_opaque(v)
      @opaque = v
    end
    protected :set_opaque

    def opaque=(v)
      check_opaque(v)
      set_opaque(v)
    end

=begin

--- URI::Generic#fragment

--- URI::Generic#fragment=(v)

=end
    #
    # methods for fragment
    #

    def check_fragment(v)
      return v unless v

      if v && v != '' && FRAGMENT !~ v
	raise InvalidComponentError, 
	  "bad component(expected fragment component): #{v}"
      end

      return true
    end
    private :check_fragment

    def set_fragment(v)
      @fragment = v
    end
    protected :set_fragment

    def fragment=(v)
      check_fragment(v)
      set_fragment(v)
    end

=begin

--- URI::Generic#hierarchical?

=end
    def hierarchical?
      if @path
	true
      else
	false
      end
    end

=begin

--- URI::Generic#absolute?

=end
    def absolute?
      if @scheme
	true
      else
	false
      end
    end
    alias absolute absolute?

=begin

--- URI::Generic#relative?

=end
    def relative?
      !absolute?
    end

=begin

--- URI::Generic#merge(rel)
--- URI::Generic#+(rel)

=end
    def split_path(path)
      path.split(%r{/+}, -1)
    end
    private :split_path

    def merge_path(base, rel)
      # RFC2396, Section 5.2, 5)
      if rel[0] == ?/ #/
	# RFC2396, Section 5.2, 5)
	return rel

      else
	# RFC2396, Section 5.2, 6)
	base_path = split_path(base)
	rel_path  = split_path(rel)

	if base_path.empty?
	  base_path = [''] # XXX
	end

	# RFC2396, Section 5.2, 6), a)
	base_path.pop if !base_path.last.empty?

	# RFC2396, Section 5.2, 6), c)
 	# RFC2396, Section 5.2, 6), d)
	rel_path.push('') if rel_path.last == '.'
	rel_path.delete('.')

	# RFC2396, Section 5.2, 6), e)
	tmp = []
	rel_path.each do |x|
	  if x == '..' &&
	      !(tmp.empty? || tmp.last == '..')
	    tmp.pop
	  else
	    tmp << x
	  end
	end

	add_trailer_slash = true
	while x = tmp.shift
	  if x == '..' && base_path.size > 1
	    # RFC2396, Section 4
	    # a .. or . in an absolute path has no special meaning
	    base_path.pop
	  else
	    # if x == '..'
	    #   valid absolute (but abnormal) path "/../..."
	    # else
	    #   valid absolute path
	    # end
	    base_path << x
	    base_path += tmp
	    add_trailer_slash = false
	    break
	  end
	end
	base_path.push('') if add_trailer_slash

	return base_path.join('/')
      end
    end
    private :merge_path

    # abs(self) + rel(oth) => abs(new)
    def merge(oth)
      base, rel = merge0(oth)
      if base == rel
	return base
      end

      authority = rel.userinfo || rel.host || rel.port

      # RFC2396, Section 5.2, 2)
      if rel.path.empty? && !authority && !rel.query
	base.set_fragment(rel.fragment) if rel.fragment
	return base
      end

      base.set_query(nil)
      base.set_fragment(nil)

      # RFC2396, Section 5.2, 4)
      if !authority
	base.set_path(merge_path(base.path, rel.path))
      else
	# RFC2396, Section 5.2, 4)
	base.set_path(rel.path)
      end

      # RFC2396, Section 5.2, 7)
      base.set_userinfo(rel.userinfo) if rel.userinfo
      base.set_host(rel.host)         if rel.host
      base.set_port(rel.port)         if rel.port
      base.set_query(rel.query)       if rel.query
      base.set_fragment(rel.fragment) if rel.fragment

      return base
    end # merge
    alias + merge

    # return base and rel.
    # you can modify `base', but can not `rel'.
    def merge0(oth)
      case oth
      when Generic
      when String
	oth = URI.parse(oth)
      else
	raise ArgumentError,
	  "bad argument(expected URI object or URI string)"
      end

      if self.relative? && oth.relative?
	raise BadURIError, 
	  "both URI are relative"
      end

      if self.absolute? && oth.absolute?
	#raise BadURIError, 
	#  "both URI are absolute"
	# hmm... should return oth for usability?
	return oth, oth
      end

      if !self.hierarchical?
	raise BadURIError, 
	  "not hierarchical URI: #{self}"
      elsif !oth.hierarchical?
	raise BadURIError, 
	  "not hierarchical URI: #{oth}"
      end

      if self.absolute?
	return self.dup, oth
      else
	return oth.dup, self
      end
    end
    private :merge0

=begin

--- URI::Generic#route_from(src)
--- URI::Generic#-(src)

=end
    def route_from_path(src, dst)
      # RFC2396, Section 4.2
      return '' if src == dst

      src_path = split_path(src)
      dst_path = split_path(dst)

      # hmm... dst has abnormal absolute path, 
      # like "/./", "/../", "/x/../", ...
      if dst_path.include?('..') ||
	  dst_path.include?('.')
	return dst.dup
      end

      src_path.pop

      # discard same parts
      while dst_path.first == src_path.first
	break if dst_path.empty?

	src_path.shift
	dst_path.shift
      end

      tmp = dst_path.join('/')

      # calculate
      if src_path.empty?
	if tmp.empty?
	  return './'
	elsif dst_path.first.include?(':') # (see RFC2396 Section 5)
	  return './' + tmp
	else
	  return tmp
	end
      end

      return '../' * src_path.size + tmp
    end
    private :route_from_path

    def route_from0(oth)
      case oth
      when Generic
      when String
	oth = URI.parse(oth)
      else
	raise ArgumentError,
	  "bad argument(expected URI object or URI string)"
      end

      if self.relative?
	raise BadURIError, 
	  "relative URI: #{self}"
      end
      if oth.relative?
	raise BadURIError, 
	  "relative URI: #{oth}"
      end

      if !self.hierarchical? || !oth.hierarchical?
	return self, self.dup
      end

      if self.scheme != oth.scheme
	return oth, oth.dup
      end
      rel = URI::Generic.new(nil, # it is relative URI
			     self.userinfo, self.host, self.port, 
			     self.registry, self.path, self.opaque,
			     self.query, self.fragment)

      if rel.userinfo != oth.userinfo ||
	  rel.host != oth.host ||
	  rel.port != oth.port
	rel.set_port(nil) if rel.port == oth.default_port
	return rel, rel
      end
      rel.set_userinfo(nil)
      rel.set_host(nil)
      rel.set_port(nil)

      if rel.path == oth.path
	rel.set_path('')
	rel.set_query(nil) if rel.query == oth.query
	return rel, rel
      end

      # you can modify `rel', but can not `oth'.
      return oth, rel
    end
    private :route_from0

    # calculate relative path from oth to self
    def route_from(oth)
      # you can modify `rel', but can not `oth'.
      oth, rel = route_from0(oth)
      if oth == rel
	return rel
      end

      rel.set_path(route_from_path(oth.path, self.path))
      if rel.path == './' && self.query
	# "./?foo" -> "?foo"
	rel.set_path('')
      end

      return rel
    end
    # abs1 - abs2 => relative_path_to_abs1_from_abs2
    # (see http://www.nikonet.or.jp/spring/what_v/what_v_4.htm :-)
    alias - route_from

=begin

--- URI::Generic#route_to(dst)

=end
    # calculate relative path to oth from self
    def route_to(oth)
      case oth
      when Generic
      when String
	oth = URI.parse(oth)
      else
	raise ArgumentError,
	  "bad argument(expected URI object or URI string)"
      end

      oth.route_from(self)
    end

=begin

--- URI::Generic#normalize
--- URI::Generic#normalize!

=end
    def normalize
      uri = dup
      uri.normalize!
      uri
    end

    def normalize!
      if path && path == ''
	set_path('/')
      end
      if host && host != host.downcase
	set_host(self.host.downcase)
      end	
    end

=begin

--- URI::Generic#to_s

=end
    def path_query
      str = @path
      if @query
	str += '?' + @query
      end
      str
    end
    private :path_query

    def to_str
      str = ''
      if @scheme
	str << @scheme
	str << ':'
      end

      if @opaque
	str << @opaque

      else
	if @registry
	  str << @registry
	else
	  if @host
	    str << '//'
	  end
	  if self.userinfo
	    str << self.userinfo
	    str << '@'
	  end
	  if @host
	    str << @host
	  end
	  if @port && @port != self.default_port
	    str << ':'
	    str << @port.to_s
	  end
	end

	str << path_query
      end

      if @fragment
	str << '#'
	str << @fragment
      end

      str
    end

    def to_s
      to_str
    end

=begin

--- URI::Generic#==(oth)

=end
    def ==(oth)
      if oth.kind_of?(String)
	oth = URI.parse(oth)
      end

      if self.class == oth.class
	self.normalize.to_ary == oth.normalize.to_ary
      else
	false
      end
    end

=begin

--- URI::Generic#===(oth)

=end
#    def ===(oth)
#      raise NotImplementedError
#    end

=begin
--- URI::Generic#to_a
=end
    def to_ary
      component.collect do |x|
	self.send(x)
      end
    end

    def to_a
      to_ary
    end

=begin
=end
    def inspect
      sprintf("#<%s:0x%x URL:%s>", self.type.to_s, self.id, self.to_s)
    end

=begin
=end
    def coerce(oth)
      case oth
      when String
	oth = URI.parse(oth)
      else
	super
      end

      return oth, self
    end
  end # Generic
end # URI
