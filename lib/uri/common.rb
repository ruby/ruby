# = uri/common.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# Revision:: $Id$
# License::
#   You can redistribute it and/or modify it under the same term as Ruby.
#

module URI
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
      UNRESERVED = "-_.!~*'()#{ALNUM}"
      # reserved      = ";" | "/" | "?" | ":" | "@" | "&" | "=" | "+" |
      #                 "$" | ","
      # reserved      = ";" | "/" | "?" | ":" | "@" | "&" | "=" | "+" |
      #                 "$" | "," | "[" | "]" (RFC 2732)
      RESERVED = ";/?:@&=+$,\\[\\]"

      # uric          = reserved | unreserved | escaped
      URIC = "(?:[#{UNRESERVED}#{RESERVED}]|#{ESCAPED})"
      # uric_no_slash = unreserved | escaped | ";" | "?" | ":" | "@" |
      #                 "&" | "=" | "+" | "$" | ","
      URIC_NO_SLASH = "(?:[#{UNRESERVED};?:@&=+$,]|#{ESCAPED})"
      # query         = *uric
      QUERY = "#{URIC}*"
      # fragment      = *uric
      FRAGMENT = "#{URIC}*"

      # domainlabel   = alphanum | alphanum *( alphanum | "-" ) alphanum
      DOMLABEL = "(?:[#{ALNUM}](?:[-#{ALNUM}]*[#{ALNUM}])?)"
      # toplabel      = alpha | alpha *( alphanum | "-" ) alphanum
      TOPLABEL = "(?:[#{ALPHA}](?:[-#{ALNUM}]*[#{ALNUM}])?)"
      # hostname      = *( domainlabel "." ) toplabel [ "." ]
      HOSTNAME = "(?:#{DOMLABEL}\\.)*#{TOPLABEL}\\.?"

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
      IPV4ADDR = "\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}"
      # hex4     = 1*4HEXDIG
      HEX4 = "[#{HEX}]{1,4}"
      # lastpart = hex4 | IPv4address
      LASTPART = "(?:#{HEX4}|#{IPV4ADDR})"
      # hexseq1  = *( hex4 ":" ) hex4
      HEXSEQ1 = "(?:#{HEX4}:)*#{HEX4}"
      # hexseq2  = *( hex4 ":" ) lastpart
      HEXSEQ2 = "(?:#{HEX4}:)*#{LASTPART}"
      # IPv6address = hexseq2 | [ hexseq1 ] "::" [ hexseq2 ]
      IPV6ADDR = "(?:#{HEXSEQ2}|(?:#{HEXSEQ1})?::(?:#{HEXSEQ2})?)"

      # IPv6prefix  = ( hexseq1 | [ hexseq1 ] "::" [ hexseq1 ] ) "/" 1*2DIGIT
      # unused

      # ipv6reference = "[" IPv6address "]" (RFC 2732)
      IPV6REF = "\\[#{IPV6ADDR}\\]"

      # host          = hostname | IPv4address
      # host          = hostname | IPv4address | IPv6reference (RFC 2732)
      HOST = "(?:#{HOSTNAME}|#{IPV4ADDR}|#{IPV6REF})"
      # port          = *digit
      PORT = '\d*'
      # hostport      = host [ ":" port ]
      HOSTPORT = "#{HOST}(?::#{PORT})?"

      # userinfo      = *( unreserved | escaped |
      #                    ";" | ":" | "&" | "=" | "+" | "$" | "," )
      USERINFO = "(?:[#{UNRESERVED};:&=+$,]|#{ESCAPED})*"

      # pchar         = unreserved | escaped |
      #                 ":" | "@" | "&" | "=" | "+" | "$" | ","
      PCHAR = "(?:[#{UNRESERVED}:@&=+$,]|#{ESCAPED})"
      # param         = *pchar
      PARAM = "#{PCHAR}*"
      # segment       = *pchar *( ";" param )
      SEGMENT = "#{PCHAR}*(?:;#{PARAM})*"
      # path_segments = segment *( "/" segment )
      PATH_SEGMENTS = "#{SEGMENT}(?:/#{SEGMENT})*"

      # server        = [ [ userinfo "@" ] hostport ]
      SERVER = "(?:#{USERINFO}@)?#{HOSTPORT}"
      # reg_name      = 1*( unreserved | escaped | "$" | "," |
      #                     ";" | ":" | "@" | "&" | "=" | "+" )
      REG_NAME = "(?:[#{UNRESERVED}$,;:@&=+]|#{ESCAPED})+"
      # authority     = server | reg_name
      AUTHORITY = "(?:#{SERVER}|#{REG_NAME})"

      # rel_segment   = 1*( unreserved | escaped |
      #                     ";" | "@" | "&" | "=" | "+" | "$" | "," )
      REL_SEGMENT = "(?:[#{UNRESERVED};@&=+$,]|#{ESCAPED})+"

      # scheme        = alpha *( alpha | digit | "+" | "-" | "." )
      SCHEME = "[#{ALPHA}][-+.#{ALPHA}\\d]*"

      # abs_path      = "/"  path_segments
      ABS_PATH = "/#{PATH_SEGMENTS}"
      # rel_path      = rel_segment [ abs_path ]
      REL_PATH = "#{REL_SEGMENT}(?:#{ABS_PATH})?"
      # net_path      = "//" authority [ abs_path ]
      NET_PATH   = "//#{AUTHORITY}(?:#{ABS_PATH})?"

      # hier_part     = ( net_path | abs_path ) [ "?" query ]
      HIER_PART   = "(?:#{NET_PATH}|#{ABS_PATH})(?:\\?(?:#{QUERY}))?"
      # opaque_part   = uric_no_slash *uric
      OPAQUE_PART = "#{URIC_NO_SLASH}#{URIC}*"

      # absoluteURI   = scheme ":" ( hier_part | opaque_part )
      ABS_URI   = "#{SCHEME}:(?:#{HIER_PART}|#{OPAQUE_PART})"
      # relativeURI   = ( net_path | abs_path | rel_path ) [ "?" query ]
      REL_URI = "(?:#{NET_PATH}|#{ABS_PATH}|#{REL_PATH})(?:\\?#{QUERY})?"

      # URI-reference = [ absoluteURI | relativeURI ] [ "#" fragment ]
      URI_REF = "(?:#{ABS_URI}|#{REL_URI})?(?:##{FRAGMENT})?"

      # XXX:
      X_ABS_URI = "
        (#{PATTERN::SCHEME}):                     (?# 1: scheme)
        (?:
           (#{PATTERN::OPAQUE_PART})              (?# 2: opaque)
        |
           (?:(?:
             //(?:
                 (?:(?:(#{PATTERN::USERINFO})@)?  (?# 3: userinfo)
                   (?:(#{PATTERN::HOST})(?::(\\d*))?))?(?# 4: host, 5: port)
               |
                 (#{PATTERN::REG_NAME})           (?# 6: registry)
               )
             |
             (?!//))                              (?# XXX: '//' is the mark for hostport)
             (#{PATTERN::ABS_PATH})?              (?# 7: path)
           )(?:\\?(#{PATTERN::QUERY}))?           (?# 8: query)
        )
        (?:\\#(#{PATTERN::FRAGMENT}))?            (?# 9: fragment)
      "
      X_REL_URI = "
        (?:
          (?:
            //
            (?:
              (?:(#{PATTERN::USERINFO})@)?       (?# 1: userinfo)
                (#{PATTERN::HOST})?(?::(\\d*))?  (?# 2: host, 3: port)
            |
              (#{PATTERN::REG_NAME})             (?# 4: registry)
            )
          )
        |
          (#{PATTERN::REL_SEGMENT})              (?# 5: rel_segment)
        )?
        (#{PATTERN::ABS_PATH})?                  (?# 6: abs_path)
        (?:\\?(#{PATTERN::QUERY}))?              (?# 7: query)
        (?:\\#(#{PATTERN::FRAGMENT}))?           (?# 8: fragment)
      "
      # :startdoc:
    end # PATTERN

    # :stopdoc:

    # for URI::split
    ABS_URI = Regexp.new('^' + PATTERN::X_ABS_URI + '$', #'
                         Regexp::EXTENDED, 'N').freeze
    REL_URI = Regexp.new('^' + PATTERN::X_REL_URI + '$', #'
                         Regexp::EXTENDED, 'N').freeze

    # for URI::extract
    URI_REF     = Regexp.new(PATTERN::URI_REF, false, 'N').freeze
    ABS_URI_REF = Regexp.new(PATTERN::X_ABS_URI, Regexp::EXTENDED, 'N').freeze
    REL_URI_REF = Regexp.new(PATTERN::X_REL_URI, Regexp::EXTENDED, 'N').freeze

    # for URI::escape/unescape
    ESCAPED = Regexp.new(PATTERN::ESCAPED, false, 'N').freeze
    UNSAFE  = Regexp.new("[^#{PATTERN::UNRESERVED}#{PATTERN::RESERVED}]",
                         false, 'N').freeze

    # for Generic#initialize
    SCHEME   = Regexp.new("^#{PATTERN::SCHEME}$", false, 'N').freeze #"
    USERINFO = Regexp.new("^#{PATTERN::USERINFO}$", false, 'N').freeze #"
    HOST     = Regexp.new("^#{PATTERN::HOST}$", false, 'N').freeze #"
    PORT     = Regexp.new("^#{PATTERN::PORT}$", false, 'N').freeze #"
    OPAQUE   = Regexp.new("^#{PATTERN::OPAQUE_PART}$", false, 'N').freeze #"
    REGISTRY = Regexp.new("^#{PATTERN::REG_NAME}$", false, 'N').freeze #"
    ABS_PATH = Regexp.new("^#{PATTERN::ABS_PATH}$", false, 'N').freeze #"
    REL_PATH = Regexp.new("^#{PATTERN::REL_PATH}$", false, 'N').freeze #"
    QUERY    = Regexp.new("^#{PATTERN::QUERY}$", false, 'N').freeze #"
    FRAGMENT = Regexp.new("^#{PATTERN::FRAGMENT}$", false, 'N').freeze #"
    # :startdoc:
  end # REGEXP

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

  module Escape
    include REGEXP

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
    def escape(str, unsafe = UNSAFE)
      unless unsafe.kind_of?(Regexp)
        # perhaps unsafe is String object
        unsafe = Regexp.new("[#{Regexp.quote(unsafe)}]", false, 'N')
      end
      str.gsub(unsafe) do |us|
        tmp = ''
        us.each_byte do |uc|
          tmp << sprintf('%%%02X', uc)
        end
        tmp
      end
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
    def unescape(str)
      str.gsub(ESCAPED) do
        $&[1,2].hex.chr
      end
    end
    alias decode unescape
  end

  include REGEXP
  extend Escape

  @@schemes = {}

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
    case uri
    when ''
      # null uri

    when ABS_URI
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

    when REL_URI
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
      registry,                        # X
      path,                         # Y
      opaque,                        # Y
      query,
      fragment
    ]
    return ret
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
    scheme, userinfo, host, port,
      registry, path, opaque, query, fragment = self.split(uri)

    if scheme && @@schemes.include?(scheme.upcase)
      @@schemes[scheme.upcase].new(scheme, userinfo, host, port,
                                   registry, path, opaque, query,
                                   fragment)
    else
      Generic.new(scheme, userinfo, host, port,
                  registry, path, opaque, query,
                  fragment)
    end
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
  #   p URI.join("http://localhost/","main.rbx")
  #   # => #<URI::HTTP:0x2022ac02 URL:http://localhost/main.rbx>
  #
  def self.join(*str)
    u = self.parse(str[0])
    str[1 .. -1].each do |x|
      u = u.merge(x)
    end
    u
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
    if block_given?
      str.scan(regexp(schemes)) { yield $& }
      nil
    else
      result = []
      str.scan(regexp(schemes)) { result.push $& }
      result
    end
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
    unless schemes
      ABS_URI_REF
    else
      /(?=#{Regexp.union(*schemes)}:)#{PATTERN::X_ABS_URI}/xn
    end
  end

end

module Kernel
  # alias for URI.parse.
  #
  # This method is introduced at 1.8.2.
  def URI(uri_str) # :doc:
    URI.parse(uri_str)
  end
  module_function :URI
end
