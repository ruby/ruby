#
# $Id$
#
# Copyright (c) 2001 akira yamada <akira@ruby-lang.org>
# You can redistribute it and/or modify it under the same term as Ruby.
#

require 'uri/generic'

module URI

=begin

== URI::FTP

=== Super Class

((<URI::Generic>))

=end

  # RFC1738 section 3.2.
  class FTP < Generic
    DEFAULT_PORT = 21

    COMPONENT = [
      :scheme, 
      :userinfo, :host, :port,
      :path, :typecode
    ].freeze

    TYPECODE = ['a', 'i', 'd'].freeze
    TYPECODE_PREFIX = ';type='.freeze

=begin

=== Class Methods

--- URI::FTP::build
    Create a new URI::FTP object from components of URI::FTP with
    check.  It is scheme, userinfo, host, port, path and typecode. It
    provided by an Array or a Hash. typecode is "a", "i" or "d".

--- URI::FTP::new
    Create a new URI::FTP object from ``generic'' components with no
    check.

=end

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

    def self.build(args)
      tmp = Util::make_components_hash(self, args)

      if tmp[:typecode]
	if tmp[:typecode].size == 1
	  tmp[:typecode] = TYPECODE_PREFIX + tmp[:typecode] 
	end
	tmp[:path] << tmp[:typecode]
      end

      return super(tmp)
    end

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

    #
    # methods for typecode
    #

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

=begin
=end
    def merge(oth)
      tmp = super(oth)
      if self != tmp
	tmp.set_typecode(oth.typecode)
      end

      return tmp
    end

=begin
=end
    def to_str
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
  end # FTP
  @@schemes['FTP'] = FTP
end # URI
