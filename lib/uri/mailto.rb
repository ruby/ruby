# = uri/mailto.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
# Revision:: $Id$
#
# See URI for general documentation
#

require 'uri/generic'

module URI

  #
  # RFC6068, The mailto URL scheme
  #
  class MailTo < Generic
    include REGEXP

    # A Default port of nil for URI::MailTo
    DEFAULT_PORT = nil

    # An Array of the available components for URI::MailTo
    COMPONENT = [ :scheme, :to, :headers ].freeze

    # :stopdoc:
    #  "hname" and "hvalue" are encodings of an RFC 822 header name and
    #  value, respectively. As with "to", all URL reserved characters must
    #  be encoded.
    #
    #  "#mailbox" is as specified in RFC 822 [RFC822]. This means that it
    #  consists of zero or more comma-separated mail addresses, possibly
    #  including "phrase" and "comment" components. Note that all URL
    #  reserved characters in "to" must be encoded: in particular,
    #  parentheses, commas, and the percent sign ("%"), which commonly occur
    #  in the "mailbox" syntax.
    #
    #  Within mailto URLs, the characters "?", "=", "&" are reserved.

    HEADER_REGEXP  = /\A(?<hfield>(?:%\h\h|[!$'-.0-;@-Z_a-z~])*=(?:%\h\h|[!$'-.0-;@-Z_a-z~])*)(?:&\g<hfield>)*\z/
    # headers    =  "?" header *( "&" header )
    # to         =  addr-spec *("," addr-spec )
    # mailtoURI  =  "mailto:" [ to ] [ hfields ]
    TO_REGEXP = /\A(?:[!#-'*+\-\/-9=?A-Z^-~]+(?:\.[!#-'*+\-\/-9=?A-Z^-~]+)*|"(?:\\[!-~]|[!#-\[\]-~])*")@(?:[!#-'*+\-\/-9=?A-Z^-~]+(?:\.[!#-'*+\-\/-9=?A-Z^-~]+)*|\[[!-Z^-~]*\])\z/
    MAILTO_DATA_REGEXP = /\A(?<to>(?<addr-spec>(?<local-part>[!#-'*+\-\/-9=?A-Z^-~]+(?:\.[!#-'*+\-\/-9=?A-Z^-~]+)*|"(?:\\[!-~]|[!#-\[\]-~])*")@(?<domain>[!#-'*+\-\/-9=?A-Z^-~]+(?:\.[!#-'*+\-\/-9=?A-Z^-~]+)*|\[[!-Z^-~]*\]))(?:,\g<addr-spec>)*)?(?<hfields>\?(?<header>(?<hfield>(?:%\h\h|[!$'-.0-;@-Z_a-z~])*=(?:%\h\h|[!$'-.0-;@-Z_a-z~])*)(?:&\g<hfield>)*))?\z/
    # :startdoc:

    #
    # == Description
    #
    # Creates a new URI::MailTo object from components, with syntax checking.
    #
    # Components can be provided as an Array or Hash. If an Array is used,
    # the components must be supplied as [to, headers].
    #
    # If a Hash is used, the keys are the component names preceded by colons.
    #
    # The headers can be supplied as a pre-encoded string, such as
    # "subject=subscribe&cc=address", or as an Array of Arrays like
    # [['subject', 'subscribe'], ['cc', 'address']]
    #
    # Examples:
    #
    #    require 'uri'
    #
    #    m1 = URI::MailTo.build(['joe@example.com', 'subject=Ruby'])
    #    puts m1.to_s  ->  mailto:joe@example.com?subject=Ruby
    #
    #    m2 = URI::MailTo.build(['john@example.com', [['Subject', 'Ruby'], ['Cc', 'jack@example.com']]])
    #    puts m2.to_s  ->  mailto:john@example.com?Subject=Ruby&Cc=jack@example.com
    #
    #    m3 = URI::MailTo.build({:to => 'listman@example.com', :headers => [['subject', 'subscribe']]})
    #    puts m3.to_s  ->  mailto:listman@example.com?subject=subscribe
    #
    def self.build(args)
      tmp = Util::make_components_hash(self, args)

      if tmp[:to]
        tmp[:opaque] = tmp[:to]
      else
        tmp[:opaque] = ''
      end

      if tmp[:headers]
        tmp[:opaque] << '?'
        case tmp[:headers]
        when Array
          tmp[:opaque] << tmp[:headers].collect { |x|
            if x.kind_of?(Array)
              x[0] + '=' + x[1..-1].join
            else
              x.to_s
            end
          }.join('&')
        when Hash
          tmp[:opaque] << tmp[:headers].collect { |h,v|
            h + '=' + v
          }.join('&')
        else
          tmp[:opaque] << tmp[:headers].to_s
        end
      end

      return super(tmp)
    end

    #
    # == Description
    #
    # Creates a new URI::MailTo object from generic URL components with
    # no syntax checking.
    #
    # This method is usually called from URI::parse, which checks
    # the validity of each component.
    #
    def initialize(*arg)
      super(*arg)

      @to = nil
      @headers = []

      if m = MAILTO_DATA_REGEXP.match(@opaque)
        if arg[10] # arg_check
          self.to = m["to"]
          self.headers = m["header"]
        else
          set_to(m["to"])
          set_headers(m["header"])
        end

      else
        raise InvalidComponentError,
          "unrecognised opaque part for mailtoURL: #{@opaque}"
      end
    end

    # The primary e-mail address of the URL, as a String
    attr_reader :to

    # E-mail headers set by the URL, as an Array of Arrays
    attr_reader :headers

    # check the to +v+ component
    def check_to(v)
      return true unless v
      return true if v.size == 0

      if TO_REGEXP !~ v
        raise InvalidComponentError,
          "bad component(expected opaque component): #{v}"
      end

      return true
    end
    private :check_to

    # private setter for to +v+
    def set_to(v)
      @to = v
    end
    protected :set_to

    # setter for to +v+
    def to=(v)
      check_to(v)
      set_to(v)
      v
    end

    # check the headers +v+ component against either
    # * URI::Parser Regexp for :QUERY
    # * HEADER_REGEXP
    def check_headers(v)
      return true unless v
      return true if v.size == 0
      if parser.regexp[:QUERY] !~ v ||
          HEADER_REGEXP !~ v
        raise InvalidComponentError,
          "bad component(expected opaque component): #{v}"
      end

      return true
    end
    private :check_headers

    # private setter for headers +v+
    def set_headers(v)
      @headers = []
      if v
        v.split('&').each do |x|
          @headers << x.split(/=/, 2)
        end
      end
    end
    protected :set_headers

    # setter for headers +v+
    def headers=(v)
      check_headers(v)
      set_headers(v)
      v
    end

    # Constructs String from URI
    def to_s
      @scheme + ':' +
        if @to
          @to
        else
          ''
        end +
        if @headers.size > 0
          '?' + @headers.collect{|x| x.join('=')}.join('&')
        else
          ''
        end +
        if @fragment
          '#' + @fragment
        else
          ''
        end
    end

    # Returns the RFC822 e-mail text equivalent of the URL, as a String.
    #
    # Example:
    #
    #   require 'uri'
    #
    #   uri = URI.parse("mailto:ruby-list@ruby-lang.org?Subject=subscribe&cc=myaddr")
    #   uri.to_mailtext
    #   # => "To: ruby-list@ruby-lang.org\nSubject: subscribe\nCc: myaddr\n\n\n"
    #
    def to_mailtext
      to = parser.unescape(@to)
      head = ''
      body = ''
      @headers.each do |x|
        case x[0]
        when 'body'
          body = parser.unescape(x[1])
        when 'to'
          to << ', ' + parser.unescape(x[1])
        else
          head << parser.unescape(x[0]).capitalize + ': ' +
            parser.unescape(x[1])  + "\n"
        end
      end

      return "To: #{to}
#{head}
#{body}
"
    end
    alias to_rfc822text to_mailtext
  end

  @@schemes['MAILTO'] = MailTo
end
