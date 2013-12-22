#--
# = uri/common.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# Revision:: $Id$
# License::
#   You can redistribute it and/or modify it under the same term as Ruby.
#
# See URI for general documentation
#

module URI
  #
  # Includes URI::REGEXP::PATTERN
  #
  module REGEXP
    #
    # Patterns used to parse URI's
    #
    module PATTERN
      # :stopdoc:

      # RFC 2396 (URI Generic Syntax)
      # RFC 2732 (IPv6 Literal Addresses in URL's)
      # RFC 2373 (IPv6 Addressing Architecture)

      # alpha         = lowalpha | upalpha
      ALPHA = "a-zA-Z"
      # alphanum      = alpha | digit
      ALNUM = "#{ALPHA}\\d"

      # hex           = digit | "A" | "B" | "C" | "D" | "E" | "F" |
      #                         "a" | "b" | "c" | "d" | "e" | "f"
      HEX     = "a-fA-F\\d"
      # escaped       = "%" hex hex
      ESCAPED = "%[#{HEX}]{2}"
      # mark          = "-" | "_" | "." | "!" | "~" | "*" | "'" |
      #                 "(" | ")"
      # unreserved    = alphanum | mark
      UNRESERVED = "\\-_.!~*'()#{ALNUM}"
      # reserved      = ";" | "/" | "?" | ":" | "@" | "&" | "=" | "+" |
      #                 "$" | ","
      # reserved      = ";" | "/" | "?" | ":" | "@" | "&" | "=" | "+" |
      #                 "$" | "," | "[" | "]" (RFC 2732)
      RESERVED = ";/?:@&=+$,\\[\\]"

      # domainlabel   = alphanum | alphanum *( alphanum | "-" ) alphanum
      DOMLABEL = "(?:[#{ALNUM}](?:[-#{ALNUM}]*[#{ALNUM}])?)"
      # toplabel      = alpha | alpha *( alphanum | "-" ) alphanum
      TOPLABEL = "(?:[#{ALPHA}](?:[-#{ALNUM}]*[#{ALNUM}])?)"
      # hostname      = *( domainlabel "." ) toplabel [ "." ]
      HOSTNAME = "(?:#{DOMLABEL}\\.)*#{TOPLABEL}\\.?"

      # :startdoc:
    end # PATTERN

    # :startdoc:
  end # REGEXP

  # class that Parses String's into URI's
  #
  # It contains a Hash set of patterns and Regexp's that match and validate.
  #
  class Parser
    include REGEXP

    #
    # == Synopsis
    #
    #   URI::Parser.new([opts])
    #
    # == Args
    #
    # The constructor accepts a hash as options for parser.
    # Keys of options are pattern names of URI components
    # and values of options are pattern strings.
    # The constructor generates set of regexps for parsing URIs.
    #
    # You can use the following keys:
    #
    #   * :ESCAPED (URI::PATTERN::ESCAPED in default)
    #   * :UNRESERVED (URI::PATTERN::UNRESERVED in default)
    #   * :DOMLABEL (URI::PATTERN::DOMLABEL in default)
    #   * :TOPLABEL (URI::PATTERN::TOPLABEL in default)
    #   * :HOSTNAME (URI::PATTERN::HOSTNAME in default)
    #
    # == Examples
    #
    #   p = URI::Parser.new(:ESCAPED => "(?:%[a-fA-F0-9]{2}|%u[a-fA-F0-9]{4})")
    #   u = p.parse("http://example.jp/%uABCD") #=> #<URI::HTTP:0xb78cf4f8 URL:http://example.jp/%uABCD>
    #   URI.parse(u.to_s) #=> raises URI::InvalidURIError
    #
    #   s = "http://examle.com/ABCD"
    #   u1 = p.parse(s) #=> #<URI::HTTP:0xb78c3220 URL:http://example.com/ABCD>
    #   u2 = URI.parse(s) #=> #<URI::HTTP:0xb78b6d54 URL:http://example.com/ABCD>
    #   u1 == u2 #=> true
    #   u1.eql?(u2) #=> false
    #
    def initialize(opts = {})
      @pattern = initialize_pattern(opts)
      @pattern.each_value {|v| v.freeze}
      @pattern.freeze

      @regexp = initialize_regexp(@pattern)
      @regexp.each_value {|v| v.freeze}
      @regexp.freeze
    end

    # The Hash of patterns.
    #
    # see also URI::Parser.initialize_pattern
    attr_reader :pattern

    # The Hash of Regexp
    #
    # see also URI::Parser.initialize_regexp
    attr_reader :regexp

    # Returns a split URI against regexp[:ABS_URI]
    def split(uri)
      case uri
      when ''
        # null uri

      when @regexp[:ABS_URI]
        scheme, opaque, userinfo, host, port,
          registry, path, query, fragment = $~[1..-1]

        # URI-reference = [ absoluteURI | relativeURI ] [ "#" fragment ]

        # absoluteURI   = scheme ":" ( hier_part | opaque_part )
        # hier_part     = ( net_path | abs_path ) [ "?" query ]
        # opaque_part   = uric_no_slash *uric

        # abs_path      = "/"  path_segments
        # net_path      = "//" authority [ abs_path ]

        # authority     = server | reg_name
        # server        = [ [ userinfo "@" ] hostport ]

        if !scheme
          raise InvalidURIError,
            "bad URI(absolute but no scheme): #{uri}"
        end
        if !opaque && (!path && (!host && !registry))
          raise InvalidURIError,
            "bad URI(absolute but no path): #{uri}"
        end

      when @regexp[:REL_URI]
        scheme = nil
        opaque = nil

        userinfo, host, port, registry,
          rel_segment, abs_path, query, fragment = $~[1..-1]
        if rel_segment && abs_path
          path = rel_segment + abs_path
        elsif rel_segment
          path = rel_segment
        elsif abs_path
          path = abs_path
        end

        # URI-reference = [ absoluteURI | relativeURI ] [ "#" fragment ]

        # relativeURI   = ( net_path | abs_path | rel_path ) [ "?" query ]

        # net_path      = "//" authority [ abs_path ]
        # abs_path      = "/"  path_segments
        # rel_path      = rel_segment [ abs_path ]

        # authority     = server | reg_name
        # server        = [ [ userinfo "@" ] hostport ]

      else
        raise InvalidURIError, "bad URI(is not URI?): #{uri}"
      end

      path = '' if !path && !opaque # (see RFC2396 Section 5.2)
      ret = [
        scheme,
        userinfo, host, port,         # X
        registry,                     # X
        path,                         # Y
        opaque,                       # Y
        query,
        fragment
      ]
      return ret
    end

    #
    # == Args
    #
    # +uri+::
    #    String
    #
    # == Description
    #
    # parses +uri+ and constructs either matching URI scheme object
    # (FTP, HTTP, HTTPS, LDAP, LDAPS, or MailTo) or URI::Generic
    #
    # == Usage
    #
    #   p = URI::Parser.new
    #   p.parse("ldap://ldap.example.com/dc=example?user=john")
    #   #=> #<URI::LDAP:0x00000000b9e7e8 URL:ldap://ldap.example.com/dc=example?user=john>
    #
    def parse(uri)
      scheme, userinfo, host, port,
        registry, path, opaque, query, fragment = self.split(uri)

      if scheme && URI.scheme_list.include?(scheme.upcase)
        URI.scheme_list[scheme.upcase].new(scheme, userinfo, host, port,
                                           registry, path, opaque, query,
                                           fragment, self)
      else
        Generic.new(scheme, userinfo, host, port,
                    registry, path, opaque, query,
                    fragment, self)
      end
    end


    #
    # == Args
    #
    # +uris+::
    #    an Array of Strings
    #
    # == Description
    #
    # Attempts to parse and merge a set of URIs
    #
    def join(*uris)
      uris[0] = convert_to_uri(uris[0])
      uris.inject :merge
    end

    #
    # :call-seq:
    #   extract( str )
    #   extract( str, schemes )
    #   extract( str, schemes ) {|item| block }
    #
    # == Args
    #
    # +str+::
    #    String to search
    # +schemes+::
    #    Patterns to apply to +str+
    #
    # == Description
    #
    # Attempts to parse and merge a set of URIs
    # If no +block+ given , then returns the result,
    # else it calls +block+ for each element in result.
    #
    # see also URI::Parser.make_regexp
    #
    def extract(str, schemes = nil)
      if block_given?
        str.scan(make_regexp(schemes)) { yield $& }
        nil
      else
        result = []
        str.scan(make_regexp(schemes)) { result.push $& }
        result
      end
    end

    # returns Regexp that is default self.regexp[:ABS_URI_REF],
    # unless +schemes+ is provided. Then it is a Regexp.union with self.pattern[:X_ABS_URI]
    def make_regexp(schemes = nil)
      unless schemes
        @regexp[:ABS_URI_REF]
      else
        /(?=#{Regexp.union(*schemes)}:)#{@pattern[:X_ABS_URI]}/x
      end
    end

    #
    # :call-seq:
    #   escape( str )
    #   escape( str, unsafe )
    #
    # == Args
    #
    # +str+::
    #    String to make safe
    # +unsafe+::
    #    Regexp to apply. Defaults to self.regexp[:UNSAFE]
    #
    # == Description
    #
    # constructs a safe String from +str+, removing unsafe characters,
    # replacing them with codes.
    #
    def escape(str, unsafe = @regexp[:UNSAFE])
      unless unsafe.kind_of?(Regexp)
        # perhaps unsafe is String object
        unsafe = Regexp.new("[#{Regexp.quote(unsafe)}]", false)
      end
      str.gsub(unsafe) do
        us = $&
        tmp = ''
        us.each_byte do |uc|
          tmp << sprintf('%%%02X', uc)
        end
        tmp
      end.force_encoding(Encoding::US_ASCII)
    end

    #
    # :call-seq:
    #   unescape( str )
    #   unescape( str, unsafe )
    #
    # == Args
    #
    # +str+::
    #    String to remove escapes from
    # +unsafe+::
    #    Regexp to apply. Defaults to self.regexp[:ESCAPED]
    #
    # == Description
    #
    # Removes escapes from +str+
    #
    def unescape(str, escaped = @regexp[:ESCAPED])
      str.gsub(escaped) { [$&[1, 2].hex].pack('C') }.force_encoding(str.encoding)
    end

    @@to_s = Kernel.instance_method(:to_s)
    def inspect
      @@to_s.bind(self).call
    end

    private

    # Constructs the default Hash of patterns
    def initialize_pattern(opts = {})
      ret = {}
      ret[:ESCAPED] = escaped = (opts.delete(:ESCAPED) || PATTERN::ESCAPED)
      ret[:UNRESERVED] = unreserved = opts.delete(:UNRESERVED) || PATTERN::UNRESERVED
      ret[:RESERVED] = reserved = opts.delete(:RESERVED) || PATTERN::RESERVED
      ret[:DOMLABEL] = opts.delete(:DOMLABEL) || PATTERN::DOMLABEL
      ret[:TOPLABEL] = opts.delete(:TOPLABEL) || PATTERN::TOPLABEL
      ret[:HOSTNAME] = hostname = opts.delete(:HOSTNAME)

      # RFC 2396 (URI Generic Syntax)
      # RFC 2732 (IPv6 Literal Addresses in URL's)
      # RFC 2373 (IPv6 Addressing Architecture)

      # uric          = reserved | unreserved | escaped
      ret[:URIC] = uric = "(?:[#{unreserved}#{reserved}]|#{escaped})"
      # uric_no_slash = unreserved | escaped | ";" | "?" | ":" | "@" |
      #                 "&" | "=" | "+" | "$" | ","
      ret[:URIC_NO_SLASH] = uric_no_slash = "(?:[#{unreserved};?:@&=+$,]|#{escaped})"
      # query         = *uric
      ret[:QUERY] = query = "#{uric}*"
      # fragment      = *uric
      ret[:FRAGMENT] = fragment = "#{uric}*"

      # hostname      = *( domainlabel "." ) toplabel [ "." ]
      # reg-name      = *( unreserved / pct-encoded / sub-delims ) # RFC3986
      unless hostname
        ret[:HOSTNAME] = hostname = "(?:[a-zA-Z0-9\\-.]|%\\h\\h)+"
      end

      # RFC 2373, APPENDIX B:
      # IPv6address = hexpart [ ":" IPv4address ]
      # IPv4address   = 1*3DIGIT "." 1*3DIGIT "." 1*3DIGIT "." 1*3DIGIT
      # hexpart = hexseq | hexseq "::" [ hexseq ] | "::" [ hexseq ]
      # hexseq  = hex4 *( ":" hex4)
      # hex4    = 1*4HEXDIG
      #
      # XXX: This definition has a flaw. "::" + IPv4address must be
      # allowed too.  Here is a replacement.
      #
      # IPv4address = 1*3DIGIT "." 1*3DIGIT "." 1*3DIGIT "." 1*3DIGIT
      ret[:IPV4ADDR] = ipv4addr = "\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}"
      # hex4     = 1*4HEXDIG
      hex4 = "[#{PATTERN::HEX}]{1,4}"
      # lastpart = hex4 | IPv4address
      lastpart = "(?:#{hex4}|#{ipv4addr})"
      # hexseq1  = *( hex4 ":" ) hex4
      hexseq1 = "(?:#{hex4}:)*#{hex4}"
      # hexseq2  = *( hex4 ":" ) lastpart
      hexseq2 = "(?:#{hex4}:)*#{lastpart}"
      # IPv6address = hexseq2 | [ hexseq1 ] "::" [ hexseq2 ]
      ret[:IPV6ADDR] = ipv6addr = "(?:#{hexseq2}|(?:#{hexseq1})?::(?:#{hexseq2})?)"

      # IPv6prefix  = ( hexseq1 | [ hexseq1 ] "::" [ hexseq1 ] ) "/" 1*2DIGIT
      # unused

      # ipv6reference = "[" IPv6address "]" (RFC 2732)
      ret[:IPV6REF] = ipv6ref = "\\[#{ipv6addr}\\]"

      # host          = hostname | IPv4address
      # host          = hostname | IPv4address | IPv6reference (RFC 2732)
      ret[:HOST] = host = "(?:#{hostname}|#{ipv4addr}|#{ipv6ref})"
      # port          = *digit
      port = '\d*'
      # hostport      = host [ ":" port ]
      ret[:HOSTPORT] = hostport = "#{host}(?::#{port})?"

      # userinfo      = *( unreserved | escaped |
      #                    ";" | ":" | "&" | "=" | "+" | "$" | "," )
      ret[:USERINFO] = userinfo = "(?:[#{unreserved};:&=+$,]|#{escaped})*"

      # pchar         = unreserved | escaped |
      #                 ":" | "@" | "&" | "=" | "+" | "$" | ","
      pchar = "(?:[#{unreserved}:@&=+$,]|#{escaped})"
      # param         = *pchar
      param = "#{pchar}*"
      # segment       = *pchar *( ";" param )
      segment = "#{pchar}*(?:;#{param})*"
      # path_segments = segment *( "/" segment )
      ret[:PATH_SEGMENTS] = path_segments = "#{segment}(?:/#{segment})*"

      # server        = [ [ userinfo "@" ] hostport ]
      server = "(?:#{userinfo}@)?#{hostport}"
      # reg_name      = 1*( unreserved | escaped | "$" | "," |
      #                     ";" | ":" | "@" | "&" | "=" | "+" )
      ret[:REG_NAME] = reg_name = "(?:[#{unreserved}$,;:@&=+]|#{escaped})+"
      # authority     = server | reg_name
      authority = "(?:#{server}|#{reg_name})"

      # rel_segment   = 1*( unreserved | escaped |
      #                     ";" | "@" | "&" | "=" | "+" | "$" | "," )
      ret[:REL_SEGMENT] = rel_segment = "(?:[#{unreserved};@&=+$,]|#{escaped})+"

      # scheme        = alpha *( alpha | digit | "+" | "-" | "." )
      ret[:SCHEME] = scheme = "[#{PATTERN::ALPHA}][\\-+.#{PATTERN::ALPHA}\\d]*"

      # abs_path      = "/"  path_segments
      ret[:ABS_PATH] = abs_path = "/#{path_segments}"
      # rel_path      = rel_segment [ abs_path ]
      ret[:REL_PATH] = rel_path = "#{rel_segment}(?:#{abs_path})?"
      # net_path      = "//" authority [ abs_path ]
      ret[:NET_PATH] = net_path = "//#{authority}(?:#{abs_path})?"

      # hier_part     = ( net_path | abs_path ) [ "?" query ]
      ret[:HIER_PART] = hier_part = "(?:#{net_path}|#{abs_path})(?:\\?(?:#{query}))?"
      # opaque_part   = uric_no_slash *uric
      ret[:OPAQUE_PART] = opaque_part = "#{uric_no_slash}#{uric}*"

      # absoluteURI   = scheme ":" ( hier_part | opaque_part )
      ret[:ABS_URI] = abs_uri = "#{scheme}:(?:#{hier_part}|#{opaque_part})"
      # relativeURI   = ( net_path | abs_path | rel_path ) [ "?" query ]
      ret[:REL_URI] = rel_uri = "(?:#{net_path}|#{abs_path}|#{rel_path})(?:\\?#{query})?"

      # URI-reference = [ absoluteURI | relativeURI ] [ "#" fragment ]
      ret[:URI_REF] = "(?:#{abs_uri}|#{rel_uri})?(?:##{fragment})?"

      ret[:X_ABS_URI] = "
        (#{scheme}):                           (?# 1: scheme)
        (?:
           (#{opaque_part})                    (?# 2: opaque)
        |
           (?:(?:
             //(?:
                 (?:(?:(#{userinfo})@)?        (?# 3: userinfo)
                   (?:(#{host})(?::(\\d*))?))? (?# 4: host, 5: port)
               |
                 (#{reg_name})                 (?# 6: registry)
               )
             |
             (?!//))                           (?# XXX: '//' is the mark for hostport)
             (#{abs_path})?                    (?# 7: path)
           )(?:\\?(#{query}))?                 (?# 8: query)
        )
        (?:\\#(#{fragment}))?                  (?# 9: fragment)
      "

      ret[:X_REL_URI] = "
        (?:
          (?:
            //
            (?:
              (?:(#{userinfo})@)?       (?# 1: userinfo)
                (#{host})?(?::(\\d*))?  (?# 2: host, 3: port)
            |
              (#{reg_name})             (?# 4: registry)
            )
          )
        |
          (#{rel_segment})              (?# 5: rel_segment)
        )?
        (#{abs_path})?                  (?# 6: abs_path)
        (?:\\?(#{query}))?              (?# 7: query)
        (?:\\#(#{fragment}))?           (?# 8: fragment)
      "

      ret
    end

    # Constructs the default Hash of Regexp's
    def initialize_regexp(pattern)
      ret = {}

      # for URI::split
      ret[:ABS_URI] = Regexp.new('\A\s*' + pattern[:X_ABS_URI] + '\s*\z', Regexp::EXTENDED)
      ret[:REL_URI] = Regexp.new('\A\s*' + pattern[:X_REL_URI] + '\s*\z', Regexp::EXTENDED)

      # for URI::extract
      ret[:URI_REF]     = Regexp.new(pattern[:URI_REF])
      ret[:ABS_URI_REF] = Regexp.new(pattern[:X_ABS_URI], Regexp::EXTENDED)
      ret[:REL_URI_REF] = Regexp.new(pattern[:X_REL_URI], Regexp::EXTENDED)

      # for URI::escape/unescape
      ret[:ESCAPED] = Regexp.new(pattern[:ESCAPED])
      ret[:UNSAFE]  = Regexp.new("[^#{pattern[:UNRESERVED]}#{pattern[:RESERVED]}]")

      # for Generic#initialize
      ret[:SCHEME]   = Regexp.new("\\A#{pattern[:SCHEME]}\\z")
      ret[:USERINFO] = Regexp.new("\\A#{pattern[:USERINFO]}\\z")
      ret[:HOST]     = Regexp.new("\\A#{pattern[:HOST]}\\z")
      ret[:PORT]     = Regexp.new("\\A#{pattern[:PORT]}\\z")
      ret[:OPAQUE]   = Regexp.new("\\A#{pattern[:OPAQUE_PART]}\\z")
      ret[:REGISTRY] = Regexp.new("\\A#{pattern[:REG_NAME]}\\z")
      ret[:ABS_PATH] = Regexp.new("\\A#{pattern[:ABS_PATH]}\\z")
      ret[:REL_PATH] = Regexp.new("\\A#{pattern[:REL_PATH]}\\z")
      ret[:QUERY]    = Regexp.new("\\A#{pattern[:QUERY]}\\z")
      ret[:FRAGMENT] = Regexp.new("\\A#{pattern[:FRAGMENT]}\\z")

      ret
    end

    def convert_to_uri(uri)
      if uri.is_a?(URI::Generic)
        uri
      elsif uri = String.try_convert(uri)
        parse(uri)
      else
        raise ArgumentError,
          "bad argument (expected URI object or URI string)"
      end
    end

  end # class Parser

  # URI::Parser.new
  DEFAULT_PARSER = Parser.new
  DEFAULT_PARSER.pattern.each_pair do |sym, str|
    unless REGEXP::PATTERN.const_defined?(sym)
      REGEXP::PATTERN.const_set(sym, str)
    end
  end
  DEFAULT_PARSER.regexp.each_pair do |sym, str|
    const_set(sym, str)
  end

  module Util # :nodoc:
    def make_components_hash(klass, array_hash)
      tmp = {}
      if array_hash.kind_of?(Array) &&
          array_hash.size == klass.component.size - 1
        klass.component[1..-1].each_index do |i|
          begin
            tmp[klass.component[i + 1]] = array_hash[i].clone
          rescue TypeError
            tmp[klass.component[i + 1]] = array_hash[i]
          end
        end

      elsif array_hash.kind_of?(Hash)
        array_hash.each do |key, value|
          begin
            tmp[key] = value.clone
          rescue TypeError
            tmp[key] = value
          end
        end
      else
        raise ArgumentError,
          "expected Array of or Hash of components of #{klass.to_s} (#{klass.component[1..-1].join(', ')})"
      end
      tmp[:scheme] = klass.to_s.sub(/\A.*::/, '').downcase

      return tmp
    end
    module_function :make_components_hash
  end

  # module for escaping unsafe characters with codes.
  module Escape
    #
    # == Synopsis
    #
    #   URI.escape(str [, unsafe])
    #
    # == Args
    #
    # +str+::
    #   String to replaces in.
    # +unsafe+::
    #   Regexp that matches all symbols that must be replaced with codes.
    #   By default uses <tt>REGEXP::UNSAFE</tt>.
    #   When this argument is a String, it represents a character set.
    #
    # == Description
    #
    # Escapes the string, replacing all unsafe characters with codes.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   enc_uri = URI.escape("http://example.com/?a=\11\15")
    #   p enc_uri
    #   # => "http://example.com/?a=%09%0D"
    #
    #   p URI.unescape(enc_uri)
    #   # => "http://example.com/?a=\t\r"
    #
    #   p URI.escape("@?@!", "!?")
    #   # => "@%3F@%21"
    #
    def escape(*arg)
      warn "#{caller(1)[0]}: warning: URI.escape is obsolete" if $VERBOSE
      DEFAULT_PARSER.escape(*arg)
    end
    alias encode escape
    #
    # == Synopsis
    #
    #   URI.unescape(str)
    #
    # == Args
    #
    # +str+::
    #   Unescapes the string.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   enc_uri = URI.escape("http://example.com/?a=\11\15")
    #   p enc_uri
    #   # => "http://example.com/?a=%09%0D"
    #
    #   p URI.unescape(enc_uri)
    #   # => "http://example.com/?a=\t\r"
    #
    def unescape(*arg)
      warn "#{caller(1)[0]}: warning: URI.unescape is obsolete" if $VERBOSE
      DEFAULT_PARSER.unescape(*arg)
    end
    alias decode unescape
  end # module Escape

  extend Escape
  include REGEXP

  @@schemes = {}
  # Returns a Hash of the defined schemes
  def self.scheme_list
    @@schemes
  end

  #
  # Base class for all URI exceptions.
  #
  class Error < StandardError; end
  #
  # Not a URI.
  #
  class InvalidURIError < Error; end
  #
  # Not a URI component.
  #
  class InvalidComponentError < Error; end
  #
  # URI is valid, bad usage is not.
  #
  class BadURIError < Error; end

  #
  # == Synopsis
  #
  #   URI::split(uri)
  #
  # == Args
  #
  # +uri+::
  #   String with URI.
  #
  # == Description
  #
  # Splits the string on following parts and returns array with result:
  #
  #   * Scheme
  #   * Userinfo
  #   * Host
  #   * Port
  #   * Registry
  #   * Path
  #   * Opaque
  #   * Query
  #   * Fragment
  #
  # == Usage
  #
  #   require 'uri'
  #
  #   p URI.split("http://www.ruby-lang.org/")
  #   # => ["http", nil, "www.ruby-lang.org", nil, nil, "/", nil, nil, nil]
  #
  def self.split(uri)
    DEFAULT_PARSER.split(uri)
  end

  #
  # == Synopsis
  #
  #   URI::parse(uri_str)
  #
  # == Args
  #
  # +uri_str+::
  #   String with URI.
  #
  # == Description
  #
  # Creates one of the URI's subclasses instance from the string.
  #
  # == Raises
  #
  # URI::InvalidURIError
  #   Raised if URI given is not a correct one.
  #
  # == Usage
  #
  #   require 'uri'
  #
  #   uri = URI.parse("http://www.ruby-lang.org/")
  #   p uri
  #   # => #<URI::HTTP:0x202281be URL:http://www.ruby-lang.org/>
  #   p uri.scheme
  #   # => "http"
  #   p uri.host
  #   # => "www.ruby-lang.org"
  #
  def self.parse(uri)
    DEFAULT_PARSER.parse(uri)
  end

  #
  # == Synopsis
  #
  #   URI::join(str[, str, ...])
  #
  # == Args
  #
  # +str+::
  #   String(s) to work with
  #
  # == Description
  #
  # Joins URIs.
  #
  # == Usage
  #
  #   require 'uri'
  #
  #   p URI.join("http://example.com/","main.rbx")
  #   # => #<URI::HTTP:0x2022ac02 URL:http://localhost/main.rbx>
  #
  #   p URI.join('http://example.com', 'foo')
  #   # => #<URI::HTTP:0x01ab80a0 URL:http://example.com/foo>
  #
  #   p URI.join('http://example.com', '/foo', '/bar')
  #   # => #<URI::HTTP:0x01aaf0b0 URL:http://example.com/bar>
  #
  #   p URI.join('http://example.com', '/foo', 'bar')
  #   # => #<URI::HTTP:0x801a92af0 URL:http://example.com/bar>
  #
  #   p URI.join('http://example.com', '/foo/', 'bar')
  #   # => #<URI::HTTP:0x80135a3a0 URL:http://example.com/foo/bar>
  #
  #
  def self.join(*str)
    DEFAULT_PARSER.join(*str)
  end

  #
  # == Synopsis
  #
  #   URI::extract(str[, schemes][,&blk])
  #
  # == Args
  #
  # +str+::
  #   String to extract URIs from.
  # +schemes+::
  #   Limit URI matching to a specific schemes.
  #
  # == Description
  #
  # Extracts URIs from a string. If block given, iterates through all matched URIs.
  # Returns nil if block given or array with matches.
  #
  # == Usage
  #
  #   require "uri"
  #
  #   URI.extract("text here http://foo.example.org/bla and here mailto:test@example.com and here also.")
  #   # => ["http://foo.example.com/bla", "mailto:test@example.com"]
  #
  def self.extract(str, schemes = nil, &block)
    DEFAULT_PARSER.extract(str, schemes, &block)
  end

  #
  # == Synopsis
  #
  #   URI::regexp([match_schemes])
  #
  # == Args
  #
  # +match_schemes+::
  #   Array of schemes. If given, resulting regexp matches to URIs
  #   whose scheme is one of the match_schemes.
  #
  # == Description
  # Returns a Regexp object which matches to URI-like strings.
  # The Regexp object returned by this method includes arbitrary
  # number of capture group (parentheses).  Never rely on it's number.
  #
  # == Usage
  #
  #   require 'uri'
  #
  #   # extract first URI from html_string
  #   html_string.slice(URI.regexp)
  #
  #   # remove ftp URIs
  #   html_string.sub(URI.regexp(['ftp'])
  #
  #   # You should not rely on the number of parentheses
  #   html_string.scan(URI.regexp) do |*matches|
  #     p $&
  #   end
  #
  def self.regexp(schemes = nil)
    DEFAULT_PARSER.make_regexp(schemes)
  end

  TBLENCWWWCOMP_ = {} # :nodoc:
  256.times do |i|
    TBLENCWWWCOMP_[i.chr] = '%%%02X' % i
  end
  TBLENCWWWCOMP_[' '] = '+'
  TBLENCWWWCOMP_.freeze
  TBLDECWWWCOMP_ = {} # :nodoc:
  256.times do |i|
    h, l = i>>4, i&15
    TBLDECWWWCOMP_['%%%X%X' % [h, l]] = i.chr
    TBLDECWWWCOMP_['%%%x%X' % [h, l]] = i.chr
    TBLDECWWWCOMP_['%%%X%x' % [h, l]] = i.chr
    TBLDECWWWCOMP_['%%%x%x' % [h, l]] = i.chr
  end
  TBLDECWWWCOMP_['+'] = ' '
  TBLDECWWWCOMP_.freeze

  HTML5ASCIIINCOMPAT = [Encoding::UTF_7, Encoding::UTF_16BE, Encoding::UTF_16LE,
    Encoding::UTF_32BE, Encoding::UTF_32LE] # :nodoc:

  # Encode given +str+ to URL-encoded form data.
  #
  # This method doesn't convert *, -, ., 0-9, A-Z, _, a-z, but does convert SP
  # (ASCII space) to + and converts others to %XX.
  #
  # If +enc+ is given, convert +str+ to the encoding before percent encoding.
  #
  # This is an implementation of
  # http://www.w3.org/TR/html5/forms.html#url-encoded-form-data
  #
  # See URI.decode_www_form_component, URI.encode_www_form
  def self.encode_www_form_component(str, enc=nil)
    str = str.to_s.dup
    if str.encoding != Encoding::ASCII_8BIT
      if enc && enc != Encoding::ASCII_8BIT
        str.encode!(Encoding::UTF_8, invalid: :replace, undef: :replace)
        str.encode!(enc, fallback: ->(x){"&#{x.ord};"})
      end
      str.force_encoding(Encoding::ASCII_8BIT)
    end
    str.gsub!(/[^*\-.0-9A-Z_a-z]/, TBLENCWWWCOMP_)
    str.force_encoding(Encoding::US_ASCII)
  end

  # Decode given +str+ of URL-encoded form data.
  #
  # This decodes + to SP.
  #
  # See URI.encode_www_form_component, URI.decode_www_form
  def self.decode_www_form_component(str, enc=Encoding::UTF_8)
    raise ArgumentError, "invalid %-encoding (#{str})" unless /\A[^%]*(?:%\h\h[^%]*)*\z/ =~ str
    str.b.gsub(/\+|%\h\h/, TBLDECWWWCOMP_).force_encoding(enc)
  end

  # Generate URL-encoded form data from given +enum+.
  #
  # This generates application/x-www-form-urlencoded data defined in HTML5
  # from given an Enumerable object.
  #
  # This internally uses URI.encode_www_form_component(str).
  #
  # This method doesn't convert the encoding of given items, so convert them
  # before call this method if you want to send data as other than original
  # encoding or mixed encoding data. (Strings which are encoded in an HTML5
  # ASCII incompatible encoding are converted to UTF-8.)
  #
  # This method doesn't handle files.  When you send a file, use
  # multipart/form-data.
  #
  # This refers http://url.spec.whatwg.org/#concept-urlencoded-serializer
  #
  #    URI.encode_www_form([["q", "ruby"], ["lang", "en"]])
  #    #=> "q=ruby&lang=en"
  #    URI.encode_www_form("q" => "ruby", "lang" => "en")
  #    #=> "q=ruby&lang=en"
  #    URI.encode_www_form("q" => ["ruby", "perl"], "lang" => "en")
  #    #=> "q=ruby&q=perl&lang=en"
  #    URI.encode_www_form([["q", "ruby"], ["q", "perl"], ["lang", "en"]])
  #    #=> "q=ruby&q=perl&lang=en"
  #
  # See URI.encode_www_form_component, URI.decode_www_form
  def self.encode_www_form(enum, enc=nil)
    enum.map do |k,v|
      if v.nil?
        encode_www_form_component(k, enc)
      elsif v.respond_to?(:to_ary)
        v.to_ary.map do |w|
          str = encode_www_form_component(k, enc)
          unless w.nil?
            str << '='
            str << encode_www_form_component(w, enc)
          end
        end.join('&')
      else
        str = encode_www_form_component(k, enc)
        str << '='
        str << encode_www_form_component(v, enc)
      end
    end.join('&')
  end

  # Decode URL-encoded form data from given +str+.
  #
  # This decodes application/x-www-form-urlencoded data
  # and returns array of key-value array.
  #
  # This refers http://url.spec.whatwg.org/#concept-urlencoded-parser ,
  # so this supports only &-separator, don't support ;-separator.
  #
  # ary = URI.decode_www_form("a=1&a=2&b=3")
  # p ary                  #=> [['a', '1'], ['a', '2'], ['b', '3']]
  # p ary.assoc('a').last  #=> '1'
  # p ary.assoc('b').last  #=> '3'
  # p ary.rassoc('a').last #=> '2'
  # p Hash[ary]            # => {"a"=>"2", "b"=>"3"}
  #
  # See URI.decode_www_form_component, URI.encode_www_form
  def self.decode_www_form(str, enc=Encoding::UTF_8, separator: '&', use__charset_: false, isindex: false)
    raise ArgumentError, "the input of #{self.name}.#{__method__} must be ASCII only string" unless str.ascii_only?
    ary = []
    return ary if str.empty?
    enc = Encoding.find(enc)
    str.b.each_line(separator) do |string|
      string.chomp!(separator)
      key, sep, val = string.partition('=')
      if isindex
        if sep.empty?
          val = key
          key = ''
        end
        isindex = false
      end

      if use__charset_ and key == '_charset_' and e = get_encoding(val)
        enc = e
        use__charset_ = false
      end

      key.gsub!(/\+|%\h\h/, TBLDECWWWCOMP_)
      if val
        val.gsub!(/\+|%\h\h/, TBLDECWWWCOMP_)
      else
        val = ''
      end

      ary << [key, val]
    end
    ary.each do |k, v|
      k.force_encoding(enc)
      k.scrub!
      v.force_encoding(enc)
      v.scrub!
    end
    ary
  end

  private
  # curl http://encoding.spec.whatwg.org/encodings.json|rb -rpp -rjson -e'H={};h={"shift_jis"=>"Windows-31J","euc-jp"=>"cp51932","iso-2022-jp"=>"cp50221","x-mac-cyrillic"=>"macCyrillic"};JSON($<.read).map{|x|x["encodings"]}.flatten.each{|x|Encoding.find(n=h.fetch(n=x["name"],n))rescue next;x["labels"].each{|y|H[y]=n}};pp H'
  WEB_ENCODINGS_ = {
    "unicode-1-1-utf-8"=>"utf-8",
    "utf-8"=>"utf-8",
    "utf8"=>"utf-8",
    "866"=>"ibm866",
    "cp866"=>"ibm866",
    "csibm866"=>"ibm866",
    "ibm866"=>"ibm866",
    "csisolatin2"=>"iso-8859-2",
    "iso-8859-2"=>"iso-8859-2",
    "iso-ir-101"=>"iso-8859-2",
    "iso8859-2"=>"iso-8859-2",
    "iso88592"=>"iso-8859-2",
    "iso_8859-2"=>"iso-8859-2",
    "iso_8859-2:1987"=>"iso-8859-2",
    "l2"=>"iso-8859-2",
    "latin2"=>"iso-8859-2",
    "csisolatin3"=>"iso-8859-3",
    "iso-8859-3"=>"iso-8859-3",
    "iso-ir-109"=>"iso-8859-3",
    "iso8859-3"=>"iso-8859-3",
    "iso88593"=>"iso-8859-3",
    "iso_8859-3"=>"iso-8859-3",
    "iso_8859-3:1988"=>"iso-8859-3",
    "l3"=>"iso-8859-3",
    "latin3"=>"iso-8859-3",
    "csisolatin4"=>"iso-8859-4",
    "iso-8859-4"=>"iso-8859-4",
    "iso-ir-110"=>"iso-8859-4",
    "iso8859-4"=>"iso-8859-4",
    "iso88594"=>"iso-8859-4",
    "iso_8859-4"=>"iso-8859-4",
    "iso_8859-4:1988"=>"iso-8859-4",
    "l4"=>"iso-8859-4",
    "latin4"=>"iso-8859-4",
    "csisolatincyrillic"=>"iso-8859-5",
    "cyrillic"=>"iso-8859-5",
    "iso-8859-5"=>"iso-8859-5",
    "iso-ir-144"=>"iso-8859-5",
    "iso8859-5"=>"iso-8859-5",
    "iso88595"=>"iso-8859-5",
    "iso_8859-5"=>"iso-8859-5",
    "iso_8859-5:1988"=>"iso-8859-5",
    "arabic"=>"iso-8859-6",
    "asmo-708"=>"iso-8859-6",
    "csiso88596e"=>"iso-8859-6",
    "csiso88596i"=>"iso-8859-6",
    "csisolatinarabic"=>"iso-8859-6",
    "ecma-114"=>"iso-8859-6",
    "iso-8859-6"=>"iso-8859-6",
    "iso-8859-6-e"=>"iso-8859-6",
    "iso-8859-6-i"=>"iso-8859-6",
    "iso-ir-127"=>"iso-8859-6",
    "iso8859-6"=>"iso-8859-6",
    "iso88596"=>"iso-8859-6",
    "iso_8859-6"=>"iso-8859-6",
    "iso_8859-6:1987"=>"iso-8859-6",
    "csisolatingreek"=>"iso-8859-7",
    "ecma-118"=>"iso-8859-7",
    "elot_928"=>"iso-8859-7",
    "greek"=>"iso-8859-7",
    "greek8"=>"iso-8859-7",
    "iso-8859-7"=>"iso-8859-7",
    "iso-ir-126"=>"iso-8859-7",
    "iso8859-7"=>"iso-8859-7",
    "iso88597"=>"iso-8859-7",
    "iso_8859-7"=>"iso-8859-7",
    "iso_8859-7:1987"=>"iso-8859-7",
    "sun_eu_greek"=>"iso-8859-7",
    "csiso88598e"=>"iso-8859-8",
    "csisolatinhebrew"=>"iso-8859-8",
    "hebrew"=>"iso-8859-8",
    "iso-8859-8"=>"iso-8859-8",
    "iso-8859-8-e"=>"iso-8859-8",
    "iso-ir-138"=>"iso-8859-8",
    "iso8859-8"=>"iso-8859-8",
    "iso88598"=>"iso-8859-8",
    "iso_8859-8"=>"iso-8859-8",
    "iso_8859-8:1988"=>"iso-8859-8",
    "visual"=>"iso-8859-8",
    "csisolatin6"=>"iso-8859-10",
    "iso-8859-10"=>"iso-8859-10",
    "iso-ir-157"=>"iso-8859-10",
    "iso8859-10"=>"iso-8859-10",
    "iso885910"=>"iso-8859-10",
    "l6"=>"iso-8859-10",
    "latin6"=>"iso-8859-10",
    "iso-8859-13"=>"iso-8859-13",
    "iso8859-13"=>"iso-8859-13",
    "iso885913"=>"iso-8859-13",
    "iso-8859-14"=>"iso-8859-14",
    "iso8859-14"=>"iso-8859-14",
    "iso885914"=>"iso-8859-14",
    "csisolatin9"=>"iso-8859-15",
    "iso-8859-15"=>"iso-8859-15",
    "iso8859-15"=>"iso-8859-15",
    "iso885915"=>"iso-8859-15",
    "iso_8859-15"=>"iso-8859-15",
    "l9"=>"iso-8859-15",
    "iso-8859-16"=>"iso-8859-16",
    "cskoi8r"=>"koi8-r",
    "koi"=>"koi8-r",
    "koi8"=>"koi8-r",
    "koi8-r"=>"koi8-r",
    "koi8_r"=>"koi8-r",
    "koi8-u"=>"koi8-u",
    "dos-874"=>"windows-874",
    "iso-8859-11"=>"windows-874",
    "iso8859-11"=>"windows-874",
    "iso885911"=>"windows-874",
    "tis-620"=>"windows-874",
    "windows-874"=>"windows-874",
    "cp1250"=>"windows-1250",
    "windows-1250"=>"windows-1250",
    "x-cp1250"=>"windows-1250",
    "cp1251"=>"windows-1251",
    "windows-1251"=>"windows-1251",
    "x-cp1251"=>"windows-1251",
    "ansi_x3.4-1968"=>"windows-1252",
    "ascii"=>"windows-1252",
    "cp1252"=>"windows-1252",
    "cp819"=>"windows-1252",
    "csisolatin1"=>"windows-1252",
    "ibm819"=>"windows-1252",
    "iso-8859-1"=>"windows-1252",
    "iso-ir-100"=>"windows-1252",
    "iso8859-1"=>"windows-1252",
    "iso88591"=>"windows-1252",
    "iso_8859-1"=>"windows-1252",
    "iso_8859-1:1987"=>"windows-1252",
    "l1"=>"windows-1252",
    "latin1"=>"windows-1252",
    "us-ascii"=>"windows-1252",
    "windows-1252"=>"windows-1252",
    "x-cp1252"=>"windows-1252",
    "cp1253"=>"windows-1253",
    "windows-1253"=>"windows-1253",
    "x-cp1253"=>"windows-1253",
    "cp1254"=>"windows-1254",
    "csisolatin5"=>"windows-1254",
    "iso-8859-9"=>"windows-1254",
    "iso-ir-148"=>"windows-1254",
    "iso8859-9"=>"windows-1254",
    "iso88599"=>"windows-1254",
    "iso_8859-9"=>"windows-1254",
    "iso_8859-9:1989"=>"windows-1254",
    "l5"=>"windows-1254",
    "latin5"=>"windows-1254",
    "windows-1254"=>"windows-1254",
    "x-cp1254"=>"windows-1254",
    "cp1255"=>"windows-1255",
    "windows-1255"=>"windows-1255",
    "x-cp1255"=>"windows-1255",
    "cp1256"=>"windows-1256",
    "windows-1256"=>"windows-1256",
    "x-cp1256"=>"windows-1256",
    "cp1257"=>"windows-1257",
    "windows-1257"=>"windows-1257",
    "x-cp1257"=>"windows-1257",
    "cp1258"=>"windows-1258",
    "windows-1258"=>"windows-1258",
    "x-cp1258"=>"windows-1258",
    "x-mac-cyrillic"=>"macCyrillic",
    "x-mac-ukrainian"=>"macCyrillic",
    "chinese"=>"gbk",
    "csgb2312"=>"gbk",
    "csiso58gb231280"=>"gbk",
    "gb2312"=>"gbk",
    "gb_2312"=>"gbk",
    "gb_2312-80"=>"gbk",
    "gbk"=>"gbk",
    "iso-ir-58"=>"gbk",
    "x-gbk"=>"gbk",
    "gb18030"=>"gb18030",
    "big5"=>"big5",
    "big5-hkscs"=>"big5",
    "cn-big5"=>"big5",
    "csbig5"=>"big5",
    "x-x-big5"=>"big5",
    "cseucpkdfmtjapanese"=>"cp51932",
    "euc-jp"=>"cp51932",
    "x-euc-jp"=>"cp51932",
    "csiso2022jp"=>"cp50221",
    "iso-2022-jp"=>"cp50221",
    "csshiftjis"=>"Windows-31J",
    "ms_kanji"=>"Windows-31J",
    "shift-jis"=>"Windows-31J",
    "shift_jis"=>"Windows-31J",
    "sjis"=>"Windows-31J",
    "windows-31j"=>"Windows-31J",
    "x-sjis"=>"Windows-31J",
    "cseuckr"=>"euc-kr",
    "csksc56011987"=>"euc-kr",
    "euc-kr"=>"euc-kr",
    "iso-ir-149"=>"euc-kr",
    "korean"=>"euc-kr",
    "ks_c_5601-1987"=>"euc-kr",
    "ks_c_5601-1989"=>"euc-kr",
    "ksc5601"=>"euc-kr",
    "ksc_5601"=>"euc-kr",
    "windows-949"=>"euc-kr",
    "utf-16be"=>"utf-16be",
    "utf-16"=>"utf-16le",
    "utf-16le"=>"utf-16le"
  } # :nodoc:

  # :nodoc:
  # return encoding or nil
  # http://encoding.spec.whatwg.org/#concept-encoding-get
  def self.get_encoding(label)
    Encoding.find(WEB_ENCODINGS_[label.to_str.strip.downcase]) rescue nil
  end
end # module URI

module Kernel

  #
  # Returns +uri+ converted to a URI object.
  #
  def URI(uri)
    if uri.is_a?(URI::Generic)
      uri
    elsif uri = String.try_convert(uri)
      URI.parse(uri)
    else
      raise ArgumentError,
        "bad argument (expected URI object or URI string)"
    end
  end
  module_function :URI
end
