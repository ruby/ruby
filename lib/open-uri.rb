#= open-uri.rb
#
#open-uri.rb is easy-to-use wrapper for net/http and net/ftp.
# 
#== Example
#
#It is possible to open http/ftp URL as usual a file:
#
#  open("http://www.ruby-lang.org/") {|f|
#    f.each_line {|line| p line}
#  }
#
#The opened file has several methods for meta information as follows since
#it is extended by OpenURI::Meta.
#
#  open("http://www.ruby-lang.org/en") {|f|
#    f.each_line {|line| p line}
#    p f.base_uri         # <URI::HTTP:0x40e6ef2 URL:http://www.ruby-lang.org/en/>
#    p f.content_type     # "text/html"
#    p f.charset          # "iso-8859-1"
#    p f.content_encoding # []
#    p f.last_modified    # Thu Dec 05 02:45:02 UTC 2002
#  }
#
#Additional header fields can be specified by an optional hash argument.
#
#  open("http://www.ruby-lang.org/en/",
#    "User-Agent" => "Ruby/#{RUBY_VERSION}",
#    "From" => "foo@bar.invalid",
#    "Referer" => "http://www.ruby-lang.org/") {|f|
#    ...
#  }
#
#The environment variables such as http_proxy and ftp_proxy are in effect by
#default.  :proxy => nil disables proxy.
#
#  open("http://www.ruby-lang.org/en/raa.html",
#    :proxy => nil) {|f|
#    ...
#  }
#
#URI objects can be opened in similar way.
# 
#  uri = URI.parse("http://www.ruby-lang.org/en/")
#  uri.open {|f|
#    ...
#  }
#
#URI objects can be read directly.
#The returned string is also extended by OpenURI::Meta.
#
#  str = uri.read
#  p str.base_uri
#
#Author:: Tanaka Akira <akr@m17n.org>

require 'uri'
require 'stringio'
require 'time'

module Kernel
  private
  alias open_uri_original_open open # :nodoc:

  # makes possible to open URIs.
  # If the first argument is URI::HTTP, URI::FTP or 
  # String beginning with http:// or ftp://,
  # the URI is opened.
  # The opened file object is extended by OpenURI::Meta.
  def open(name, *rest, &block)
    if name.respond_to?("open")
      name.open(*rest, &block)
    elsif name.respond_to?("to_str") && %r{\A(http|ftp)://} =~ name
      OpenURI.open_uri(name, *rest, &block)
    else
      open_uri_original_open(name, *rest, &block)
    end
  end
  module_function :open
end

module OpenURI
  def OpenURI.scan_open_optional_arguments(*rest) # :nodoc:
    if !rest.empty? && (String === rest.first || Integer === rest.first)
      mode = rest.shift
      if !rest.empty? && Integer === rest.first
        perm = rest.shift
      end
    end
    return mode, perm, rest
  end

  def OpenURI.open_uri(name, *rest) # :nodoc:
    uri = URI::Generic === name ? name : URI.parse(name)
    mode, perm, rest = OpenURI.scan_open_optional_arguments(*rest)
    options = rest.shift if !rest.empty? && Hash === rest.first
    raise ArgumentError.new("extra arguments") if !rest.empty?

    unless mode == nil ||
           mode == 'r' || mode == 'rb' ||
           mode == O_RDONLY
      raise ArgumentError.new("invalid access mode #{mode} (#{uri.class} resource is read only.)")
    end

    io = open_loop(uri, options || {})
    if block_given?
      begin
        yield io
      ensure
        io.close
      end
    else
      io
    end
  end

  def OpenURI.open_loop(uri, options) # :nodoc:
    header = {}
    options.each {|k, v|
      if String === k
        header[k] = v
      end
    }

    case opt_proxy = options.fetch(:proxy, true)
    when true
      find_proxy = lambda {|u| u.find_proxy}
    when nil, false
      find_proxy = lambda {|u| nil}
    when String
      opt_proxy = URI.parse(opt_proxy)
      find_proxy = lambda {|u| opt_proxy}
    when URI::Generic
      find_proxy = lambda {|u| opt_proxy}
    else
      raise ArgumentError.new("Invalid proxy option: #{opt_proxy}")
    end

    uri_set = {}
    begin
      buf = Buffer.new
      if proxy_uri = find_proxy.call(uri)
        proxy_uri.proxy_open(buf, uri, header)
      else
        uri.direct_open(buf, header)
      end
    rescue Redirect
      loc = $!.uri
      if loc.relative?
        # Although it violates RFC 2616, Location: field may have relative URI.
        # It is converted to absolute URI using uri.
        loc = uri + loc
      end
      uri = loc
      raise "HTTP redirection loop: #{uri}" if uri_set.include? uri.to_s
      uri_set[uri.to_s] = true 
      retry
    end
    io = buf.io
    io.base_uri = uri
    io
  end

  class Redirect < StandardError # :nodoc:
    def initialize(uri)
      super("redirection to #{uri.to_s}")
      @uri = uri
    end
    attr_reader :uri
  end

  class HTTPError < StandardError
    def initialize(message, io)
      super(message)
      @io = io
    end
    attr_reader :io
  end

  class Buffer # :nodoc:
    def initialize
      @io = StringIO.new
    end

    StringMax = 10240
    def <<(str)
      @io << str
      if StringIO === @io && StringMax < @io.size
        require 'tempfile'
        io = Tempfile.new('open-uri')
        Meta.init io, @io if Meta === @io
        io << @io.string
        @io = io
      end
    end

    def io
      Meta.init @io unless Meta === @io
      @io
    end
  end

  # Mixin for holding meta-information.
  module Meta
    def Meta.init(obj, src=nil) # :nodoc:
      obj.extend Meta
      obj.instance_eval {
        @base_uri = nil
        @meta = {}
      }
      if src
        obj.status = src.status
        obj.base_uri = src.base_uri
        src.meta.each {|name, value|
          obj.meta_add_field(name, value)
        }
      end
    end

    # returns an Array which consits status code and message.
    attr_accessor :status

    # returns a URI which is base of relative URIs in the data.
    # It may differ from the URI supplied by a user because redirection.
    attr_accessor :base_uri

    # returns a Hash which represents header fields.
    # The Hash keys are downcased for canonicalization.
    attr_reader :meta

    def meta_add_field(name, value) # :nodoc:
      @meta[name.downcase] = value
    end

    # returns a Time which represents Last-Modified field.
    def last_modified
      if v = @meta['last-modified']
        Time.httpdate(v)
      else
        nil
      end
    end

    RE_LWS = /[\r\n\t ]+/n
    RE_TOKEN = %r{[^\x00- ()<>@,;:\\"/\[\]?={}\x7f]+}n
    RE_QUOTED_STRING = %r{"(?:[\r\n\t !#-\[\]-~\x80-\xff]|\\[\x00-\x7f])"}n
    RE_PARAMETERS = %r{(?:;#{RE_LWS}?#{RE_TOKEN}#{RE_LWS}?=#{RE_LWS}?(?:#{RE_TOKEN}|#{RE_QUOTED_STRING})#{RE_LWS}?)*}n

    def content_type_parse # :nodoc:
      v = @meta['content-type']
      if v && %r{\A#{RE_LWS}?(#{RE_TOKEN})#{RE_LWS}?/(#{RE_TOKEN})#{RE_LWS}?(#{RE_PARAMETERS})\z}o =~ v
        type = $1.downcase
        subtype = $2.downcase
        parameters = []
        $3.scan(/;#{RE_LWS}?(#{RE_TOKEN})#{RE_LWS}?=#{RE_LWS}?(?:(#{RE_TOKEN})|(#{RE_QUOTED_STRING}))/o) {|att, val, qval|
          val = qval.gsub(/[\r\n\t !#-\[\]-~\x80-\xff]+|(\\[\x00-\x7f])/) { $1 ? $1[1,1] : $& } if qval
          parameters << [att.downcase, val]
        }
        ["#{type}/#{subtype}", *parameters]
      else
        nil
      end
    end

    # returns "type/subtype" which is MIME Content-Type.
    # It is downcased for canonicalization.
    # Content-Type parameters are stripped.
    def content_type
      type, *parameters = content_type_parse
      type || 'application/octet-stream'
    end

    # returns a charset parameter in Content-Type field.
    # It is downcased for canonicalization.
    #
    # If charset parameter is not given but a block is given,
    # the block is called and its result is returned.
    # It can be used to guess charset.
    #
    # If charset parameter and block is not given,
    # nil is returned except text type in HTTP.
    # In that case, "iso-8859-1" is returned as defined by RFC2616 3.7.1.
    def charset
      type, *parameters = content_type_parse
      if pair = parameters.assoc('charset')
        pair.last.downcase
      elsif block_given?
        yield
      elsif type && %r{\Atext/} =~ type &&
            @base_uri && @base_uri.scheme == 'http'
        "iso-8859-1" # RFC2616 3.7.1
      else
        nil
      end
    end

    # returns a list of encodings in Content-Encoding field
    # as an Array of String.
    # The encodings are downcased for canonicalization.
    def content_encoding
      v = @meta['content-encoding']
      if v && %r{\A#{RE_LWS}?#{RE_TOKEN}#{RE_LWS}?(?:,#{RE_LWS}?#{RE_TOKEN}#{RE_LWS}?)*}o =~ v
        v.scan(RE_TOKEN).map {|content_coding| content_coding.downcase}
      else
        []
      end
    end
  end

  # Mixin for URIs.
  module OpenRead
    # opens the URI.  
    def open(*rest, &block)
      OpenURI.open_uri(self, *rest, &block)
    end

    # reads a content of the URI.  
    def read(options={})
      self.open(options) {|f|
        str = f.read
        Meta.init str, f
        str
      }
    end
  end
end

module URI
  class Generic
    # returns a proxy URI.
    # The proxy URI is obtained from environment variables such as http_proxy,
    # ftp_proxy, no_proxy, etc.
    # If there is no proper proxy, nil is returned.
    def find_proxy
      name = self.scheme + '_proxy'
      if proxy_uri = ENV[name] || ENV[name.upcase]
        proxy_uri = URI.parse(proxy_uri)
        name = 'no_proxy'
        if no_proxy = ENV[name] || ENV[name.upcase]
          no_proxy.scan(/([^:,]*)(?::(\d+))?/) {|host, port|
            if /(\A|\.)#{Regexp.quote host}\z/i =~ proxy_uri.host &&
               (!port || self.port == port.to_i)
              proxy_uri = nil
              break
            end
          }
        end
        proxy_uri
      else
        nil
      end
    end
  end

  class HTTP
    def direct_open(buf, header) # :nodoc:
      proxy_open(buf, request_uri, header)
    end

    def proxy_open(buf, uri, header) # :nodoc:
      require 'net/http'
      resp = Net::HTTP.start(self.host, self.port) {|http|
               http.get(uri.to_s, header) {|str| buf << str}
             }
      io = buf.io
      io.rewind
      io.status = [resp.code, resp.message]
      resp.each {|name,value| buf.io.meta_add_field name, value }
      case resp
      when Net::HTTPSuccess
      when Net::HTTPMovedPermanently, # 301
           Net::HTTPFound, # 302
           Net::HTTPSeeOther, # 303
           Net::HTTPTemporaryRedirect # 307
        raise OpenURI::Redirect.new(URI.parse(resp['location']))
      else
        raise OpenURI::HTTPError.new(io.status.join(' '), io)
      end
    end

    include OpenURI::OpenRead
  end

  class FTP
    def direct_open(buf, header) # :nodoc:
      require 'net/ftp'
      # xxx: header is discarded. 
      # todo: extract user/passwd from .netrc.
      user = 'anonymous'
      passwd = nil
      user, passwd = self.userinfo.split(/:/) if self.userinfo

      ftp = Net::FTP.open(self.host)
      ftp.login(user, passwd)
      ftp.getbinaryfile(self.path, '/dev/null', Net::FTP::DEFAULT_BLOCKSIZE) {|str| buf << str}
      ftp.close
      buf.io.rewind
    end

    include OpenURI::OpenRead
  end
end
