module URI
  class RFC3986_Parser # :nodoc:
    # URI defined in RFC3986
    # this regexp is modified not to host is not empty string
    RFC3986_URI = /\A(?<URI>(?<scheme>[A-Za-z][+\-.0-9A-Za-z]*):(?<hier-part>\/\/(?<authority>(?:(?<userinfo>(?:%\h\h|[!$&-.0-;=A-Z_a-z~])*)@)?(?<host>(?<IP-literal>\[(?:(?<IPv6address>(?:\h{1,4}:){6}(?<ls32>\h{1,4}:\h{1,4}|(?<IPv4address>(?<dec-octet>[1-9]\d|1\d{2}|2[0-4]\d|25[0-5]|\d)\.\g<dec-octet>\.\g<dec-octet>\.\g<dec-octet>))|::(?:\h{1,4}:){5}\g<ls32>|\h{1,4}?::(?:\h{1,4}:){4}\g<ls32>|(?:(?:\h{1,4}:)?\h{1,4})?::(?:\h{1,4}:){3}\g<ls32>|(?:(?:\h{1,4}:){,2}\h{1,4})?::(?:\h{1,4}:){2}\g<ls32>|(?:(?:\h{1,4}:){,3}\h{1,4})?::\h{1,4}:\g<ls32>|(?:(?:\h{1,4}:){,4}\h{1,4})?::\g<ls32>|(?:(?:\h{1,4}:){,5}\h{1,4})?::\h{1,4}|(?:(?:\h{1,4}:){,6}\h{1,4})?::)|(?<IPvFuture>v\h+\.[!$&-.0-;=A-Z_a-z~]+))\])|\g<IPv4address>|(?<reg-name>(?:%\h\h|[!$&-.0-9;=A-Z_a-z~])+))?(?::(?<port>\d*))?)(?<path-abempty>(?:\/(?<segment>(?:%\h\h|[!$&-.0-;=@-Z_a-z~])*))*)|(?<path-absolute>\/(?:(?<segment-nz>(?:%\h\h|[!$&-.0-;=@-Z_a-z~])+)(?:\/\g<segment>)*)?)|(?<path-rootless>\g<segment-nz>(?:\/\g<segment>)*)|(?<path-empty>))(?:\?(?<query>[^#]*))?(?:\#(?<fragment>(?:%\h\h|[!$&-.0-;=@-Z_a-z~\/?])*))?)\z/
    RFC3986_relative_ref = /\A(?<relative-ref>(?<relative-part>\/\/(?<authority>(?:(?<userinfo>(?:%\h\h|[!$&-.0-;=A-Z_a-z~])*)@)?(?<host>(?<IP-literal>\[(?<IPv6address>(?:\h{1,4}:){6}(?<ls32>\h{1,4}:\h{1,4}|(?<IPv4address>(?<dec-octet>[1-9]\d|1\d{2}|2[0-4]\d|25[0-5]|\d)\.\g<dec-octet>\.\g<dec-octet>\.\g<dec-octet>))|::(?:\h{1,4}:){5}\g<ls32>|\h{1,4}?::(?:\h{1,4}:){4}\g<ls32>|(?:(?:\h{1,4}:){,1}\h{1,4})?::(?:\h{1,4}:){3}\g<ls32>|(?:(?:\h{1,4}:){,2}\h{1,4})?::(?:\h{1,4}:){2}\g<ls32>|(?:(?:\h{1,4}:){,3}\h{1,4})?::\h{1,4}:\g<ls32>|(?:(?:\h{1,4}:){,4}\h{1,4})?::\g<ls32>|(?:(?:\h{1,4}:){,5}\h{1,4})?::\h{1,4}|(?:(?:\h{1,4}:){,6}\h{1,4})?::)|(?<IPvFuture>v\h+\.[!$&-.0-;=A-Z_a-z~]+)\])|\g<IPv4address>|(?<reg-name>(?:%\h\h|[!$&-.0-9;=A-Z_a-z~])+))?(?::(?<port>\d*))?)(?<path-abempty>(?:\/(?<segment>(?:%\h\h|[!$&-.0-;=@-Z_a-z~])*))*)|(?<path-absolute>\/(?:(?<segment-nz>(?:%\h\h|[!$&-.0-;=@-Z_a-z~])+)(?:\/\g<segment>)*)?)|(?<path-noscheme>(?<segment-nz-nc>(?:%\h\h|[!$&-.0-9;=@-Z_a-z~])+)(?:\/\g<segment>)*)|(?<path-empty>))(?:\?(?<query>[^#]*))?(?:\#(?<fragment>(?:%\h\h|[!$&-.0-;=@-Z_a-z~\/?])*))?)\z/

    def split(uri) #:nodoc:
      begin
        uri = uri.to_str
      rescue NoMethodError
        raise InvalidURIError, "bad URI(is not URI?): #{uri}"
      end
      unless uri.ascii_only?
        raise InvalidURIError, "URI must be ascii only #{uri.dump}"
      end
      if m = RFC3986_URI.match(uri)
        ary = []
        ary << m["scheme"]
        if m["path-rootless"] # opaque
          ary << nil # userinfo
          ary << nil # host
          ary << nil # port
          ary << nil # registry
          ary << nil # path
          ary << m["path-rootless"]
          ary[-1] << '?' << m["query"] if m["query"]
          ary << nil # query
          ary << m["fragment"]
        else # normal
          ary << m["userinfo"]
          ary << m["host"]
          ary << m["port"]
          ary << nil # registry
          ary << (m["path-abempty"] || m["path-absolute"] || m["path-empty"])
          ary << nil # opaque
          ary << m["query"]
          ary << m["fragment"]
        end
      elsif m = RFC3986_relative_ref.match(uri)
        ary = [nil]
        ary << m["userinfo"]
        ary << m["host"]
        ary << m["port"]
        ary << nil # registry
        ary << (m["path-abempty"] || m["path-absolute"] || m["path-noscheme"] || m["path-empty"])
        ary << nil # opaque
        ary << m["query"]
        ary << m["fragment"]
      else
        raise InvalidURIError, "bad URI(is not URI?): #{uri}"
      end
    end

    def parse(uri) # :nodoc:
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


    def join(*uris) # :nodoc:
      uris[0] = convert_to_uri(uris[0])
      uris.inject :merge
    end

    @@to_s = Kernel.instance_method(:to_s)
    def inspect
      @@to_s.bind(self).call
    end

    def regexp
      {
        SCHEME: /\A[A-Za-z][A-Za-z0-9+\-.]*\z/,
        USERINFO: /\A(?:%\h\h|[!$&-.0-;=A-Z_a-z~])*\z/,
        HOST: /\A(?:(?<IP-literal>\[(?:(?<IPv6address>(?:\h{1,4}:){6}(?<ls32>\h{1,4}:\h{1,4}|(?<IPv4address>(?<dec-octet>[1-9]\d|1\d{2}|2[0-4]\d|25[0-5]|\d)\.\g<dec-octet>\.\g<dec-octet>\.\g<dec-octet>))|::(?:\h{1,4}:){5}\g<ls32>|\h{,4}::(?:\h{1,4}:){4}\g<ls32>|(?:(?:\h{1,4}:)?\h{1,4})?::(?:\h{1,4}:){3}\g<ls32>|(?:(?:\h{1,4}:){,2}\h{1,4})?::(?:\h{1,4}:){2}\g<ls32>|(?:(?:\h{1,4}:){,3}\h{1,4})?::\h{1,4}:\g<ls32>|(?:(?:\h{1,4}:){,4}\h{1,4})?::\g<ls32>|(?:(?:\h{1,4}:){,5}\h{1,4})?::\h{1,4}|(?:(?:\h{1,4}:){,6}\h{1,4})?::)|(?<IPvFuture>v\h+\.[!$&-.0-;=A-Z_a-z~]+))\])|\g<IPv4address>|(?<reg-name>(?:%\h\h|[!$&-.0-9;=A-Z_a-z~])*))\z/,
        ABS_PATH: /\A\/(?:%\h\h|[!$&-.0-;=@-Z_a-z~])*(?:\/(?:%\h\h|[!$&-.0-;=@-Z_a-z~])*)*\z/,
        REL_PATH: /\A(?:%\h\h|[!$&-.0-;=@-Z_a-z~])+(?:\/(?:%\h\h|[!$&-.0-;=@-Z_a-z~])*)*\z/,
        QUERY: /\A(?:%\h\h|[!$&-.0-;=@-Z_a-z~\/?])*\z/,
        FRAGMENT: /\A(?:%\h\h|[!$&-.0-;=@-Z_a-z~\/?])*\z/,
        OPAQUE: /\A(?:[^\/].*)?\z/,
        PORT: /\A[\x09\x0a\x0c\x0d ]*\d*[\x09\x0a\x0c\x0d ]*\z/,
      }
    end

    private

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
end # module URI
