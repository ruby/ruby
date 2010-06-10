#
# = uri/generic.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
# Revision:: $Id$
#

require 'uri/common'

module URI
  
  #
  # Base class for all URI classes.
  # Implements generic URI syntax as per RFC 2396.
  #
  class Generic
    include URI
    include REGEXP

    DEFAULT_PORT = nil

    #
    # Returns default port
    #
    def self.default_port
      self::DEFAULT_PORT
    end

    def default_port
      self.class.default_port
    end

    COMPONENT = [
      :scheme, 
      :userinfo, :host, :port, :registry, 
      :path, :opaque, 
      :query, 
      :fragment
    ].freeze

    #
    # Components of the URI in the order.
    #
    def self.component
      self::COMPONENT
    end

    USE_REGISTRY = false

    #
    # DOC: FIXME!
    #
    def self.use_registry
      self::USE_REGISTRY
    end

    #
    # == Synopsis
    #
    # See #new
    #
    # == Description
    #
    # At first, tries to create a new URI::Generic instance using
    # URI::Generic::build. But, if exception URI::InvalidComponentError is raised, 
    # then it URI::Escape.escape all URI components and tries again.
    #
    #
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

    #
    # == Synopsis
    #
    # See #new
    #
    # == Description
    #
    # Creates a new URI::Generic instance from components of URI::Generic
    # with check.  Components are: scheme, userinfo, host, port, registry, path,
    # opaque, query and fragment. You can provide arguments either by an Array or a Hash.
    # See #new for hash keys to use or for order of array items.
    #
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
        "expected Array of or Hash of components of #{self.class} (#{self.class.component.join(', ')})"
      end

      tmp << true
      return self.new(*tmp)
    end
    #
    # == Args
    #
    # +scheme+::
    #   Protocol scheme, i.e. 'http','ftp','mailto' and so on.
    # +userinfo+::
    #   User name and password, i.e. 'sdmitry:bla'
    # +host+::
    #   Server host name
    # +port+::
    #   Server port
    # +registry+::
    #   DOC: FIXME!
    # +path+::
    #   Path on server
    # +opaque+::
    #   DOC: FIXME!
    # +query+::
    #   Query data
    # +fragment+::
    #   A part of URI after '#' sign
    # +arg_check+::
    #   Check arguments [false by default]
    #
    # == Description
    #
    # Creates a new URI::Generic instance from ``generic'' components without check.
    #
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
      if @registry && !self.class.use_registry
        raise InvalidURIError, 
          "the scheme #{@scheme} does not accept registry part: #{@registry} (or bad hostname?)"
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

    # replace self by other URI object
    def replace!(oth)
      if self.class != oth.class
        raise ArgumentError, "expected #{self.class} object"
      end

      component.each do |c|
        self.__send__("#{c}=", oth.__send__(c))
      end
    end
    private :replace!

    def component
      self.class.component
    end

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
      v
    end

    def check_userinfo(user, password = nil)
      if !password
        user, password = split_userinfo(user)
      end
      check_user(user)
      check_password(password, user)

      return true
    end
    private :check_userinfo

    def check_user(v)
      if @registry || @opaque
        raise InvalidURIError, 
          "can not set user with registry or opaque"
      end

      return v unless v

      if USERINFO !~ v
        raise InvalidComponentError,
          "bad component(expected userinfo component or user component): #{v}"
      end

      return true
    end
    private :check_user

    def check_password(v, user = @user)
      if @registry || @opaque
        raise InvalidURIError, 
          "can not set password with registry or opaque"
      end
      return v unless v

      if !user
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

    #
    # Sets userinfo, argument is string like 'name:pass'
    #
    def userinfo=(userinfo)
      if userinfo.nil?
        return nil
      end
      check_userinfo(*userinfo)
      set_userinfo(*userinfo)
      # returns userinfo
    end

    def user=(user)
      check_user(user)
      set_user(user)
      # returns user
    end
    
    def password=(password)
      check_password(password)
      set_password(password)
      # returns password
    end

    def set_userinfo(user, password = nil)
      unless password 
        user, password = split_userinfo(user)
      end
      @user     = user
      @password = password if password

      [@user, @password]
    end
    protected :set_userinfo

    def set_user(v)
      set_userinfo(v, @password)
      v
    end
    protected :set_user

    def set_password(v)
      @password = v
      # returns v
    end
    protected :set_password

    def split_userinfo(ui)
      return nil, nil unless ui
      user, password = ui.split(/:/, 2)

      return user, password
    end
    private :split_userinfo

    def escape_userpass(v)
      v = URI.escape(v, /[@:\/]/o) # RFC 1738 section 3.1 #/
    end
    private :escape_userpass

    def userinfo
      if @user.nil?
        nil
      elsif @password.nil?
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
      v
    end

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
      unless !v || v.kind_of?(Fixnum)
        if v.empty?
          v = nil
        else
          v = v.to_i
        end
      end
      @port = v
    end
    protected :set_port

    def port=(v)
      check_port(v)
      set_port(v)
      port
    end

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
      v
    end

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
            "bad component(expected relative path component): #{v}"
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
      v
    end

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
      v
    end

    def check_opaque(v)
      return v unless v

      # raise if both hier and opaque are not nil, because:
      # absoluteURI   = scheme ":" ( hier_part | opaque_part )
      # hier_part     = ( net_path | abs_path ) [ "?" query ]
      if @host || @port || @user || @path  # userinfo = @user + ':' + @password
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
      v
    end

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
      v
    end

    #
    # Checks if URI has a path
    #
    def hierarchical?
      if @path
        true
      else
        false
      end
    end

    #
    # Checks if URI is an absolute one
    #
    def absolute?
      if @scheme
        true
      else
        false
      end
    end
    alias absolute absolute?

    #
    # Checks if URI is relative
    #
    def relative?
      !absolute?
    end

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

        # RFC2396, Section 5.2, 6), a)
	base_path << '' if base_path.last == '..'
	while i = base_path.index('..')
	  base_path.slice!(i - 1, 2)
        end
        if base_path.empty?
          base_path = [''] # keep '/' for root directory
        else
	  base_path.pop
        end

        # RFC2396, Section 5.2, 6), c)
        # RFC2396, Section 5.2, 6), d)
        rel_path.push('') if rel_path.last == '.' || rel_path.last == '..'
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
            tmp.each {|t| base_path << t}
            add_trailer_slash = false
            break
          end
        end
        base_path.push('') if add_trailer_slash

        return base_path.join('/')
      end
    end
    private :merge_path

    #
    # == Args
    #
    # +oth+::
    #    URI or String
    #
    # == Description
    #
    # Destructive form of #merge
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com")
    #   uri.merge!("/main.rbx?page=1")
    #   p uri
    #   # =>  #<URI::HTTP:0x2021f3b0 URL:http://my.example.com/main.rbx?page=1>
    #
    def merge!(oth)
      t = merge(oth)
      if self == t
        nil
      else
        replace!(t)
        self
      end
    end

    #
    # == Args
    #
    # +oth+::
    #    URI or String
    #
    # == Description
    #
    # Merges two URI's.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com")
    #   p uri.merge("/main.rbx?page=1")
    #   # =>  #<URI::HTTP:0x2021f3b0 URL:http://my.example.com/main.rbx?page=1>
    #
    def merge(oth)
      begin
        base, rel = merge0(oth)
      rescue
        raise $!.class, $!.message
      end

      if base == rel
        return base
      end

      authority = rel.userinfo || rel.host || rel.port

      # RFC2396, Section 5.2, 2)
      if (rel.path.nil? || rel.path.empty?) && !authority && !rel.query
        base.set_fragment(rel.fragment) if rel.fragment
        return base
      end

      base.set_query(nil)
      base.set_fragment(nil)

      # RFC2396, Section 5.2, 4)
      if !authority
        base.set_path(merge_path(base.path, rel.path)) if base.path && rel.path
      else
        # RFC2396, Section 5.2, 4)
        base.set_path(rel.path) if rel.path
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

      if self.absolute?
        return self.dup, oth
      else
        return oth, oth
      end
    end
    private :merge0

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

      if self.scheme != oth.scheme
        return self, self.dup
      end
      rel = URI::Generic.new(nil, # it is relative URI
                             self.userinfo, self.host, self.port, 
                             self.registry, self.path, self.opaque,
                             self.query, self.fragment)

      if rel.userinfo != oth.userinfo ||
          rel.host.to_s.downcase != oth.host.to_s.downcase ||
          rel.port != oth.port
	if self.userinfo.nil? && self.host.nil?
	  return self, self.dup
	end
        rel.set_port(nil) if rel.port == oth.default_port
        return rel, rel
      end
      rel.set_userinfo(nil)
      rel.set_host(nil)
      rel.set_port(nil)

      if rel.path && rel.path == oth.path
        rel.set_path('')
        rel.set_query(nil) if rel.query == oth.query
        return rel, rel
      elsif rel.opaque && rel.opaque == oth.opaque
        rel.set_opaque('')
        rel.set_query(nil) if rel.query == oth.query
        return rel, rel
      end

      # you can modify `rel', but can not `oth'.
      return oth, rel
    end
    private :route_from0
    #
    # == Args
    #
    # +oth+::
    #    URI or String
    #
    # == Description
    #
    # Calculates relative path from oth to self
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse('http://my.example.com/main.rbx?page=1')
    #   p uri.route_from('http://my.example.com')
    #   #=> #<URI::Generic:0x20218858 URL:/main.rbx?page=1>
    #
    def route_from(oth)
      # you can modify `rel', but can not `oth'.
      begin
        oth, rel = route_from0(oth)
      rescue
        raise $!.class, $!.message
      end
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

    alias - route_from

    #
    # == Args
    #
    # +oth+::
    #    URI or String
    #
    # == Description
    #
    # Calculates relative path to oth from self
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse('http://my.example.com')
    #   p uri.route_to('http://my.example.com/main.rbx?page=1')
    #   #=> #<URI::Generic:0x2020c2f6 URL:/main.rbx?page=1>
    #    
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

    #
    # Returns normalized URI
    # 
    def normalize
      uri = dup
      uri.normalize!
      uri
    end

    #
    # Destructive version of #normalize
    #
    def normalize!
      if path && path == ''
        set_path('/')
      end
      if host && host != host.downcase
        set_host(self.host.downcase)
      end        
    end

    def path_query
      str = @path
      if @query
        str += '?' + @query
      end
      str
    end
    private :path_query

    #
    # Constructs String from URI
    # 
    def to_s
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

    #
    # Compares to URI's
    #
    def ==(oth)
      if self.class == oth.class
        self.normalize.component_ary == oth.normalize.component_ary
      else
        false
      end
    end

    def hash
      self.component_ary.hash
    end

    def eql?(oth)
      self.class == oth.class &&
      self.component_ary.eql?(oth.component_ary)
    end

=begin

--- URI::Generic#===(oth)

=end
#    def ===(oth)
#      raise NotImplementedError
#    end

=begin
=end
    def component_ary
      component.collect do |x|
        self.send(x)
      end
    end
    protected :component_ary

    # == Args
    #
    # +components+::
    #    Multiple Symbol arguments defined in URI::HTTP
    #
    # == Description
    #
    # Selects specified components from URI
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse('http://myuser:mypass@my.example.com/test.rbx')
    #   p uri.select(:userinfo, :host, :path)
    #   # => ["myuser:mypass", "my.example.com", "/test.rbx"]
    #
    def select(*components)
      components.collect do |c|
        if component.include?(c)
          self.send(c)
        else
          raise ArgumentError, 
            "expected of components of #{self.class} (#{self.class.component.join(', ')})"
        end
      end
    end

    @@to_s = Kernel.instance_method(:to_s)
    def inspect
      @@to_s.bind(self).call.sub!(/>\z/) {" URL:#{self}>"}
    end

    def coerce(oth)
      case oth
      when String
        oth = URI.parse(oth)
      else
        super
      end

      return oth, self
    end
  end
end
