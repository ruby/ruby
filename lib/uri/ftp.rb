#
# = uri/ftp.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
# Revision:: $Id$
#

require 'uri/generic'

module URI

  #
  # FTP URI syntax is defined by RFC1738 section 3.2.
  #
  class FTP < Generic
    DEFAULT_PORT = 21

    COMPONENT = [
      :scheme, 
      :userinfo, :host, :port,
      :path, :typecode
    ].freeze
    #
    # Typecode is "a", "i" or "d". 
    #
    # * "a" indicates a text file (the FTP command was ASCII)
    # * "i" indicates a binary file (FTP command IMAGE)
    # * "d" indicates the contents of a directory should be displayed
    #
    TYPECODE = ['a', 'i', 'd'].freeze
    TYPECODE_PREFIX = ';type='.freeze

    def self.new2(user, password, host, port, path, 
                  typecode = nil, arg_check = true)
      typecode = nil if typecode.size == 0
      if typecode && !TYPECODE.include?(typecode)
        raise ArgumentError,
          "bad typecode is specified: #{typecode}"
      end

      # do escape

      self.new('ftp',
               [user, password], 
               host, port, nil, 
               typecode ? path + TYPECODE_PREFIX + typecode : path, 
               nil, nil, nil, arg_check)
    end

    #
    # == Description
    #
    # Creates a new URI::FTP object from components, with syntax checking.  
    #
    # The components accepted are +userinfo+, +host+, +port+, +path+ and 
    # +typecode+.
    #
    # The components should be provided either as an Array, or as a Hash 
    # with keys formed by preceding the component names with a colon. 
    #
    # If an Array is used, the components must be passed in the order
    # [userinfo, host, port, path, typecode]
    #
    # If the path supplied is absolute, it will be escaped in order to
    # make it absolute in the URI. Examples:
    #
    #     require 'uri'
    #
    #     uri = URI::FTP.build(['user:password', 'ftp.example.com', nil, 
    #       '/path/file.> zip', 'i'])
    #     puts uri.to_s  ->  ftp://user:password@ftp.example.com/%2Fpath/file.zip;type=a
    #
    #     uri2 = URI::FTP.build({:host => 'ftp.example.com', 
    #       :path => 'ruby/src'})
    #     puts uri2.to_s  ->  ftp://ftp.example.com/ruby/src
    #
    def self.build(args)

      # Fix the incoming path to be generic URL syntax
      # FTP path  ->  URL path
      # foo/bar       /foo/bar
      # /foo/bar      /%2Ffoo/bar
      #
      if args.kind_of?(Array)
        args[3] = '/' + args[3].sub(/^\//, '%2F')
      else
        args[:path] = '/' + args[:path].sub(/^\//, '%2F')
      end

      tmp = Util::make_components_hash(self, args)

      if tmp[:typecode]
        if tmp[:typecode].size == 1
          tmp[:typecode] = TYPECODE_PREFIX + tmp[:typecode] 
        end
        tmp[:path] << tmp[:typecode]
      end

      return super(tmp)
    end

    #
    # == Description
    #
    # Creates a new URI::FTP object from generic URL components with no
    # syntax checking.
    #
    # Unlike build(), this method does not escape the path component as
    # required by RFC1738; instead it is treated as per RFC2396.
    #
    # Arguments are +scheme+, +userinfo+, +host+, +port+, +registry+, +path+, 
    # +opaque+, +query+ and +fragment+, in that order.
    #
    def initialize(*arg)
      super(*arg)
      @typecode = nil
      tmp = @path.index(TYPECODE_PREFIX)
      if tmp
        typecode = @path[tmp + TYPECODE_PREFIX.size..-1]
        self.set_path(@path[0..tmp - 1])
        
        if arg[-1]
          self.typecode = typecode
        else
          self.set_typecode(typecode)
        end
      end
    end
    attr_reader :typecode

    def check_typecode(v)
      if TYPECODE.include?(v)
        return true
      else
        raise InvalidComponentError,
          "bad typecode(expected #{TYPECODE.join(', ')}): #{v}"
      end
    end
    private :check_typecode

    def set_typecode(v)
      @typecode = v
    end
    protected :set_typecode

    def typecode=(typecode)
      check_typecode(typecode)
      set_typecode(typecode)
      typecode
    end

    def merge(oth) # :nodoc:
      tmp = super(oth)
      if self != tmp
        tmp.set_typecode(oth.typecode)
      end

      return tmp
    end

    # Returns the path from an FTP URI.
    #
    # RFC 1738 specifically states that the path for an FTP URI does not
    # include the / which separates the URI path from the URI host. Example:
    #
    #     ftp://ftp.example.com/pub/ruby 
    #
    # The above URI indicates that the client should connect to 
    # ftp.example.com then cd pub/ruby from the initial login directory.
    #
    # If you want to cd to an absolute directory, you must include an
    # escaped / (%2F) in the path. Example:
    #
    #     ftp://ftp.example.com/%2Fpub/ruby
    #
    # This method will then return "/pub/ruby"
    #
    def path
      return @path.sub(/^\//,'').sub(/^%2F/i,'/')
    end

    def to_s
      save_path = nil
      if @typecode
        save_path = @path
        @path = @path + TYPECODE_PREFIX + @typecode
      end
      str = super
      if @typecode
        @path = save_path
      end

      return str
    end
  end
  @@schemes['FTP'] = FTP
end
