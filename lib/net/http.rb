#
# = net/http.rb
#
# Copyright (c) 1999-2007 Yukihiro Matsumoto
# Copyright (c) 1999-2007 Minero Aoki
# Copyright (c) 2001 GOTOU Yuuzou
# 
# Written and maintained by Minero Aoki <aamine@loveruby.net>.
# HTTPS support added by GOTOU Yuuzou <gotoyuzo@notwork.org>.
#
# This file is derived from "http-access.rb".
#
# Documented by Minero Aoki; converted to RDoc by William Webber.
# 
# This program is free software. You can re-distribute and/or
# modify this program under the same terms of ruby itself ---
# Ruby Distribution License or GNU General Public License.
#
# See Net::HTTP for an overview and examples. 
# 
# NOTE: You can find Japanese version of this document here:
# http://www.ruby-lang.org/ja/man/html/net_http.html
# 
#--
# $Id$
#++ 

require 'net/protocol'
require 'uri'

module Net   #:nodoc:

  # :stopdoc:
  class HTTPBadResponse < StandardError; end
  class HTTPHeaderSyntaxError < StandardError; end
  # :startdoc:

  # == What Is This Library?
  # 
  # This library provides your program functions to access WWW
  # documents via HTTP, Hyper Text Transfer Protocol version 1.1.
  # For details of HTTP, refer [RFC2616]
  # (http://www.ietf.org/rfc/rfc2616.txt).
  # 
  # == Examples
  # 
  # === Getting Document From WWW Server
  # 
  # Example #1: Simple GET+print
  # 
  #     require 'net/http'
  #     Net::HTTP.get_print 'www.example.com', '/index.html'
  # 
  # Example #2: Simple GET+print by URL
  # 
  #     require 'net/http'
  #     require 'uri'
  #     Net::HTTP.get_print URI.parse('http://www.example.com/index.html')
  # 
  # Example #3: More generic GET+print
  # 
  #     require 'net/http'
  #     require 'uri'
  #
  #     url = URI.parse('http://www.example.com/index.html')
  #     res = Net::HTTP.start(url.host, url.port) {|http|
  #       http.get('/index.html')
  #     }
  #     puts res.body
  #
  # Example #4: More generic GET+print
  # 
  #     require 'net/http'
  #
  #     url = URI.parse('http://www.example.com/index.html')
  #     req = Net::HTTP::Get.new(url.path)
  #     res = Net::HTTP.start(url.host, url.port) {|http|
  #       http.request(req)
  #     }
  #     puts res.body
  # 
  # === Posting Form Data
  # 
  #     require 'net/http'
  #     require 'uri'
  #
  #     #1: Simple POST
  #     res = Net::HTTP.post_form(URI.parse('http://www.example.com/search.cgi'),
  #                               {'q' => 'ruby', 'max' => '50'})
  #     puts res.body
  #
  #     #2: POST with basic authentication
  #     res = Net::HTTP.post_form(URI.parse('http://jack:pass@www.example.com/todo.cgi'),
  #                                         {'from' => '2005-01-01',
  #                                          'to' => '2005-03-31'})
  #     puts res.body
  #
  #     #3: Detailed control
  #     url = URI.parse('http://www.example.com/todo.cgi')
  #     req = Net::HTTP::Post.new(url.path)
  #     req.basic_auth 'jack', 'pass'
  #     req.set_form_data({'from' => '2005-01-01', 'to' => '2005-03-31'}, ';')
  #     res = Net::HTTP.new(url.host, url.port).start {|http| http.request(req) }
  #     case res
  #     when Net::HTTPSuccess, Net::HTTPRedirection
  #       # OK
  #     else
  #       res.error!
  #     end
  #
  #     #4: Multiple values
  #     res = Net::HTTP.post_form(URI.parse('http://www.example.com/search.cgi'),
  #                               {'q' => ['ruby', 'perl'], 'max' => '50'})
  #     puts res.body
  # 
  # === Accessing via Proxy
  # 
  # Net::HTTP.Proxy creates http proxy class. It has same
  # methods of Net::HTTP but its instances always connect to
  # proxy, instead of given host.
  # 
  #     require 'net/http'
  # 
  #     proxy_addr = 'your.proxy.host'
  #     proxy_port = 8080
  #             :
  #     Net::HTTP::Proxy(proxy_addr, proxy_port).start('www.example.com') {|http|
  #       # always connect to your.proxy.addr:8080
  #             :
  #     }
  # 
  # Since Net::HTTP.Proxy returns Net::HTTP itself when proxy_addr is nil,
  # there's no need to change code if there's proxy or not.
  # 
  # There are two additional parameters in Net::HTTP.Proxy which allow to
  # specify proxy user name and password:
  # 
  #     Net::HTTP::Proxy(proxy_addr, proxy_port, proxy_user = nil, proxy_pass = nil)
  # 
  # You may use them to work with authorization-enabled proxies:
  # 
  #     require 'net/http'
  #     require 'uri'
  #     
  #     proxy_host = 'your.proxy.host'
  #     proxy_port = 8080
  #     uri = URI.parse(ENV['http_proxy'])
  #     proxy_user, proxy_pass = uri.userinfo.split(/:/) if uri.userinfo
  #     Net::HTTP::Proxy(proxy_host, proxy_port,
  #                      proxy_user, proxy_pass).start('www.example.com') {|http|
  #       # always connect to your.proxy.addr:8080 using specified username and password
  #             :
  #     }
  #
  # Note that net/http never rely on HTTP_PROXY environment variable.
  # If you want to use proxy, set it explicitly.
  # 
  # === Following Redirection
  # 
  #     require 'net/http'
  #     require 'uri'
  # 
  #     def fetch(uri_str, limit = 10)
  #       # You should choose better exception. 
  #       raise ArgumentError, 'HTTP redirect too deep' if limit == 0
  # 
  #       response = Net::HTTP.get_response(URI.parse(uri_str))
  #       case response
  #       when Net::HTTPSuccess     then response
  #       when Net::HTTPRedirection then fetch(response['location'], limit - 1)
  #       else
  #         response.error!
  #       end
  #     end
  # 
  #     print fetch('http://www.ruby-lang.org')
  # 
  # Net::HTTPSuccess and Net::HTTPRedirection is a HTTPResponse class.
  # All HTTPResponse objects belong to its own response class which
  # indicate HTTP result status. For details of response classes,
  # see section "HTTP Response Classes".
  # 
  # === Basic Authentication
  # 
  #     require 'net/http'
  # 
  #     Net::HTTP.start('www.example.com') {|http|
  #       req = Net::HTTP::Get.new('/secret-page.html')
  #       req.basic_auth 'account', 'password'
  #       response = http.request(req)
  #       print response.body
  #     }
  # 
  # === HTTP Request Classes
  #
  # Here is HTTP request class hierarchy.
  #
  #   Net::HTTPRequest
  #       Net::HTTP::Get
  #       Net::HTTP::Head
  #       Net::HTTP::Post
  #       Net::HTTP::Put
  #       Net::HTTP::Patch
  #       Net::HTTP::Proppatch
  #       Net::HTTP::Lock
  #       Net::HTTP::Unlock
  #       Net::HTTP::Options
  #       Net::HTTP::Propfind
  #       Net::HTTP::Delete
  #       Net::HTTP::Move
  #       Net::HTTP::Copy
  #       Net::HTTP::Mkcol
  #       Net::HTTP::Trace
  #
  # === HTTP Response Classes
  #
  # Here is HTTP response class hierarchy.
  # All classes are defined in Net module.
  #
  #   HTTPResponse
  #       HTTPUnknownResponse
  #       HTTPInformation                    # 1xx
  #           HTTPContinue                       # 100
  #           HTTPSwitchProtocl                  # 101
  #       HTTPSuccess                        # 2xx
  #           HTTPOK                             # 200
  #           HTTPCreated                        # 201
  #           HTTPAccepted                       # 202
  #           HTTPNonAuthoritativeInformation    # 203
  #           HTTPNoContent                      # 204
  #           HTTPResetContent                   # 205
  #           HTTPPartialContent                 # 206
  #       HTTPRedirection                    # 3xx
  #           HTTPMultipleChoice                 # 300
  #           HTTPMovedPermanently               # 301
  #           HTTPFound                          # 302
  #           HTTPSeeOther                       # 303
  #           HTTPNotModified                    # 304
  #           HTTPUseProxy                       # 305
  #           HTTPTemporaryRedirect              # 307
  #       HTTPClientError                    # 4xx
  #           HTTPBadRequest                     # 400
  #           HTTPUnauthorized                   # 401
  #           HTTPPaymentRequired                # 402
  #           HTTPForbidden                      # 403
  #           HTTPNotFound                       # 404
  #           HTTPMethodNotAllowed               # 405
  #           HTTPNotAcceptable                  # 406
  #           HTTPProxyAuthenticationRequired    # 407
  #           HTTPRequestTimeOut                 # 408
  #           HTTPConflict                       # 409
  #           HTTPGone                           # 410
  #           HTTPLengthRequired                 # 411
  #           HTTPPreconditionFailed             # 412
  #           HTTPRequestEntityTooLarge          # 413
  #           HTTPRequestURITooLong              # 414
  #           HTTPUnsupportedMediaType           # 415
  #           HTTPRequestedRangeNotSatisfiable   # 416
  #           HTTPExpectationFailed              # 417
  #       HTTPServerError                    # 5xx
  #           HTTPInternalServerError            # 500
  #           HTTPNotImplemented                 # 501
  #           HTTPBadGateway                     # 502
  #           HTTPServiceUnavailable             # 503
  #           HTTPGatewayTimeOut                 # 504
  #           HTTPVersionNotSupported            # 505
  # 
  # == Switching Net::HTTP versions
  # 
  # You can use net/http.rb 1.1 features (bundled with Ruby 1.6)
  # by calling HTTP.version_1_1. Calling Net::HTTP.version_1_2
  # allows you to use 1.2 features again.
  # 
  #     # example
  #     Net::HTTP.start {|http1| ...(http1 has 1.2 features)... }
  # 
  #     Net::HTTP.version_1_1
  #     Net::HTTP.start {|http2| ...(http2 has 1.1 features)... }
  # 
  #     Net::HTTP.version_1_2
  #     Net::HTTP.start {|http3| ...(http3 has 1.2 features)... }
  # 
  # This function is NOT thread-safe.
  #
  class HTTP < Protocol

    # :stopdoc:
    Revision = %q$Revision$.split[1]
    HTTPVersion = '1.1'
    @newimpl = true
    begin
      require 'zlib'
      require 'stringio'  #for our purposes (unpacking gzip) lump these together
      HAVE_ZLIB=true
    rescue LoadError
      HAVE_ZLIB=false
    end
    # :startdoc:

    # Turns on net/http 1.2 (ruby 1.8) features.
    # Defaults to ON in ruby 1.8.
    #
    # I strongly recommend to call this method always.
    #
    #   require 'net/http'
    #   Net::HTTP.version_1_2
    #
    def HTTP.version_1_2
      @newimpl = true
    end

    # Turns on net/http 1.1 (ruby 1.6) features.
    # Defaults to OFF in ruby 1.8.
    def HTTP.version_1_1
      @newimpl = false
    end

    # true if net/http is in version 1.2 mode.
    # Defaults to true.
    def HTTP.version_1_2?
      @newimpl
    end

    # true if net/http is in version 1.1 compatible mode.
    # Defaults to true.
    def HTTP.version_1_1?
      not @newimpl
    end

    class << HTTP
      alias is_version_1_1? version_1_1?   #:nodoc:
      alias is_version_1_2? version_1_2?   #:nodoc:
    end

    #
    # short cut methods
    #

    #
    # Get body from target and output it to +$stdout+.  The
    # target can either be specified as (+uri+), or as
    # (+host+, +path+, +port+ = 80); so: 
    #
    #    Net::HTTP.get_print URI.parse('http://www.example.com/index.html')
    #
    # or:
    #
    #    Net::HTTP.get_print 'www.example.com', '/index.html'
    #
    def HTTP.get_print(uri_or_host, path = nil, port = nil)
      get_response(uri_or_host, path, port) {|res|
        res.read_body do |chunk|
          $stdout.print chunk
        end
      }
      nil
    end

    # Send a GET request to the target and return the response
    # as a string.  The target can either be specified as
    # (+uri+), or as (+host+, +path+, +port+ = 80); so:
    # 
    #    print Net::HTTP.get(URI.parse('http://www.example.com/index.html'))
    #
    # or:
    #
    #    print Net::HTTP.get('www.example.com', '/index.html')
    #
    def HTTP.get(uri_or_host, path = nil, port = nil)
      get_response(uri_or_host, path, port).body
    end

    # Send a GET request to the target and return the response
    # as a Net::HTTPResponse object.  The target can either be specified as
    # (+uri+), or as (+host+, +path+, +port+ = 80); so:
    # 
    #    res = Net::HTTP.get_response(URI.parse('http://www.example.com/index.html'))
    #    print res.body
    #
    # or:
    #
    #    res = Net::HTTP.get_response('www.example.com', '/index.html')
    #    print res.body
    #
    def HTTP.get_response(uri_or_host, path = nil, port = nil, &block)
      if path
        host = uri_or_host
        new(host, port || HTTP.default_port).start {|http|
          return http.request_get(path, &block)
        }
      else
        uri = uri_or_host
        new(uri.host, uri.port).start {|http|
          return http.request_get(uri.request_uri, &block)
        }
      end
    end

    # Posts HTML form data to the +URL+.
    # Form data must be represented as a Hash of String to String, e.g:
    #
    #   { "cmd" => "search", "q" => "ruby", "max" => "50" }
    #
    # This method also does Basic Authentication iff +URL+.user exists.
    #
    # Example:
    #
    #   require 'net/http'
    #   require 'uri'
    #
    #   HTTP.post_form URI.parse('http://www.example.com/search.cgi'),
    #                  { "q" => "ruby", "max" => "50" }
    #
    def HTTP.post_form(url, params)
      req = Post.new(url.path)
      req.form_data = params
      req.basic_auth url.user, url.password if url.user
      new(url.host, url.port).start {|http|
        http.request(req)
      }
    end

    #
    # HTTP session management
    #

    # The default port to use for HTTP requests; defaults to 80.
    def HTTP.default_port
      http_default_port()
    end

    # The default port to use for HTTP requests; defaults to 80.
    def HTTP.http_default_port
      80
    end

    # The default port to use for HTTPS requests; defaults to 443.
    def HTTP.https_default_port
      443
    end

    def HTTP.socket_type   #:nodoc: obsolete
      BufferedIO
    end

    # creates a new Net::HTTP object and opens its TCP connection and 
    # HTTP session.  If the optional block is given, the newly 
    # created Net::HTTP object is passed to it and closed when the 
    # block finishes.  In this case, the return value of this method
    # is the return value of the block.  If no block is given, the
    # return value of this method is the newly created Net::HTTP object
    # itself, and the caller is responsible for closing it upon completion.
    def HTTP.start(address, port = nil, p_addr = nil, p_port = nil, p_user = nil, p_pass = nil, &block) # :yield: +http+
      new(address, port, p_addr, p_port, p_user, p_pass).start(&block)
    end

    class << HTTP
      alias newobj new
    end

    # Creates a new Net::HTTP object.
    # If +proxy_addr+ is given, creates an Net::HTTP object with proxy support.
    # This method does not open the TCP connection.
    def HTTP.new(address, port = nil, p_addr = nil, p_port = nil, p_user = nil, p_pass = nil)
      h = Proxy(p_addr, p_port, p_user, p_pass).newobj(address, port)
      h.instance_eval {
        @newimpl = ::Net::HTTP.version_1_2?
      }
      h
    end

    # Creates a new Net::HTTP object for the specified +address+.
    # This method does not open the TCP connection.
    def initialize(address, port = nil)
      @address = address
      @port    = (port || HTTP.default_port)
      @curr_http_version = HTTPVersion
      @no_keepalive_server = false
      @close_on_empty_response = false
      @socket  = nil
      @started = false
      @open_timeout = nil
      @read_timeout = 60
      @debug_output = nil
      @use_ssl = false
      @ssl_context = nil
      @enable_post_connection_check = true
      @compression = nil
      @sspi_enabled = false
      if defined?(SSL_ATTRIBUTES)
        SSL_ATTRIBUTES.each do |name|
          instance_variable_set "@#{name}", nil
        end
      end
    end

    def inspect
      "#<#{self.class} #{@address}:#{@port} open=#{started?}>"
    end

    # *WARNING* This method causes serious security hole.
    # Never use this method in production code.
    #
    # Set an output stream for debugging.
    #
    #   http = Net::HTTP.new
    #   http.set_debug_output $stderr
    #   http.start { .... }
    #
    def set_debug_output(output)
      warn 'Net::HTTP#set_debug_output called after HTTP started' if started?
      @debug_output = output
    end

    # The host name to connect to.
    attr_reader :address

    # The port number to connect to.
    attr_reader :port

    # Seconds to wait until connection is opened.
    # If the HTTP object cannot open a connection in this many seconds,
    # it raises a TimeoutError exception.
    attr_accessor :open_timeout

    # Seconds to wait until reading one block (by one read(2) call).
    # If the HTTP object cannot open a connection in this many seconds,
    # it raises a TimeoutError exception.
    attr_reader :read_timeout

    # Setter for the read_timeout attribute.
    def read_timeout=(sec)
      @socket.read_timeout = sec if @socket
      @read_timeout = sec
    end

    # returns true if the HTTP session is started.
    def started?
      @started
    end

    alias active? started?   #:nodoc: obsolete

    attr_accessor :close_on_empty_response

    # returns true if use SSL/TLS with HTTP.
    def use_ssl?
      false   # redefined in net/https
    end

    # Opens TCP connection and HTTP session.
    # 
    # When this method is called with block, gives a HTTP object
    # to the block and closes the TCP connection / HTTP session
    # after the block executed.
    #
    # When called with a block, returns the return value of the
    # block; otherwise, returns self.
    #
    def start  # :yield: http
      raise IOError, 'HTTP session already opened' if @started
      if block_given?
        begin
          do_start
          return yield(self)
        ensure
          do_finish
        end
      end
      do_start
      self
    end

    def do_start
      connect
      @started = true
    end
    private :do_start

    def connect
      D "opening connection to #{conn_address()}..."
      s = timeout(@open_timeout) { TCPSocket.open(conn_address(), conn_port()) }
      D "opened"
      if use_ssl?
        ssl_parameters = Hash.new
        SSL_ATTRIBUTES.each do |name|
          if value = instance_variable_get("@#{name}")
            ssl_parameters[name] = value
          end
        end
        @ssl_context = OpenSSL::SSL::SSLContext.new
        @ssl_context.set_params(ssl_parameters)
        s = OpenSSL::SSL::SSLSocket.new(s, @ssl_context)
        s.sync_close = true
      end
      @socket = BufferedIO.new(s)
      @socket.read_timeout = @read_timeout
      @socket.debug_output = @debug_output
      if use_ssl?
        if proxy?
          @socket.writeline sprintf('CONNECT %s:%s HTTP/%s',
                                    @address, @port, HTTPVersion)
          @socket.writeline "Host: #{@address}:#{@port}"
          if proxy_user
            credential = ["#{proxy_user}:#{proxy_pass}"].pack('m')
            credential.delete!("\r\n")
            @socket.writeline "Proxy-Authorization: Basic #{credential}"
          end
          @socket.writeline ''
          HTTPResponse.read_new(@socket).value
        end
        s.connect
        if @ssl_context.verify_mode != OpenSSL::SSL::VERIFY_NONE
          s.post_connection_check(@address)
        end
      end
      on_connect
    end
    private :connect

    def on_connect
    end
    private :on_connect

    # Finishes HTTP session and closes TCP connection.
    # Raises IOError if not started.
    def finish
      raise IOError, 'HTTP session not yet started' unless started?
      do_finish
    end

    def do_finish
      @started = false
      @socket.close if @socket and not @socket.closed?
      @socket = nil
    end
    private :do_finish

    #
    # proxy
    #

    public

    # no proxy
    @is_proxy_class = false
    @proxy_addr = nil
    @proxy_port = nil
    @proxy_user = nil
    @proxy_pass = nil

    # Creates an HTTP proxy class.
    # Arguments are address/port of proxy host and username/password
    # if authorization on proxy server is required.
    # You can replace the HTTP class with created proxy class.
    # 
    # If ADDRESS is nil, this method returns self (Net::HTTP).
    # 
    #     # Example
    #     proxy_class = Net::HTTP::Proxy('proxy.example.com', 8080)
    #                     :
    #     proxy_class.start('www.ruby-lang.org') {|http|
    #       # connecting proxy.foo.org:8080
    #                     :
    #     }
    # 
    def HTTP.Proxy(p_addr, p_port = nil, p_user = nil, p_pass = nil)
      return self unless p_addr
      delta = ProxyDelta
      proxyclass = Class.new(self)
      proxyclass.module_eval {
        include delta
        # with proxy
        @is_proxy_class = true
        @proxy_address = p_addr
        @proxy_port    = p_port || default_port()
        @proxy_user    = p_user
        @proxy_pass    = p_pass
      }
      proxyclass
    end

    class << HTTP
      # returns true if self is a class which was created by HTTP::Proxy.
      def proxy_class?
        @is_proxy_class
      end

      attr_reader :proxy_address
      attr_reader :proxy_port
      attr_reader :proxy_user
      attr_reader :proxy_pass
    end

    # True if self is a HTTP proxy class.
    def proxy?
      self.class.proxy_class?
    end

    # Address of proxy host. If self does not use a proxy, nil.
    def proxy_address
      self.class.proxy_address
    end

    # Port number of proxy host. If self does not use a proxy, nil.
    def proxy_port
      self.class.proxy_port
    end

    # User name for accessing proxy. If self does not use a proxy, nil.
    def proxy_user
      self.class.proxy_user
    end

    # User password for accessing proxy. If self does not use a proxy, nil.
    def proxy_pass
      self.class.proxy_pass
    end

    alias proxyaddr proxy_address   #:nodoc: obsolete
    alias proxyport proxy_port      #:nodoc: obsolete

    private

    # without proxy

    def conn_address
      address()
    end

    def conn_port
      port()
    end

    def edit_path(path)
      path
    end

    module ProxyDelta   #:nodoc: internal use only
      private

      def conn_address
        proxy_address()
      end

      def conn_port
        proxy_port()
      end

      def edit_path(path)
        use_ssl? ? path : "http://#{addr_port()}#{path}"
      end
    end

    #
    # HTTP operations
    #

    public

    # Gets data from +path+ on the connected-to host.
    # +initheader+ must be a Hash like { 'Accept' => '*/*', ... },
    # and it defaults to an empty hash.
    # If +initheader+ doesn't have the key 'accept-encoding', then
    # a value of "gzip;q=1.0,deflate;q=0.6,identity;q=0.3" is used,
    # so that gzip compression is used in preference to deflate 
    # compression, which is used in preference to no compression. 
    # Ruby doesn't have libraries to support the compress (Lempel-Ziv)
    # compression, so that is not supported.  The intent of this is
    # to reduce bandwidth by default.   If this routine sets up
    # compression, then it does the decompression also, removing
    # the header as well to prevent confusion.  Otherwise
    # it leaves the body as it found it. 
    #
    # In version 1.1 (ruby 1.6), this method returns a pair of objects,
    # a Net::HTTPResponse object and the entity body string.
    # In version 1.2 (ruby 1.8), this method returns a Net::HTTPResponse
    # object.
    #
    # If called with a block, yields each fragment of the
    # entity body in turn as a string as it is read from
    # the socket.  Note that in this case, the returned response
    # object will *not* contain a (meaningful) body.
    #
    # +dest+ argument is obsolete.
    # It still works but you must not use it.
    #
    # In version 1.1, this method might raise an exception for 
    # 3xx (redirect). In this case you can get a HTTPResponse object
    # by "anException.response".
    #
    # In version 1.2, this method never raises exception.
    #
    #     # version 1.1 (bundled with Ruby 1.6)
    #     response, body = http.get('/index.html')
    #
    #     # version 1.2 (bundled with Ruby 1.8 or later)
    #     response = http.get('/index.html')
    #     
    #     # using block
    #     File.open('result.txt', 'w') {|f|
    #       http.get('/~foo/') do |str|
    #         f.write str
    #       end
    #     }
    #
    def get(path, initheader = {}, dest = nil, &block) # :yield: +body_segment+
      res = nil
      if HAVE_ZLIB
        unless  initheader.keys.any?{|k| k.downcase == "accept-encoding"}
          initheader["accept-encoding"] = "gzip;q=1.0,deflate;q=0.6,identity;q=0.3"
          @compression = true
        end
      end
      request(Get.new(path, initheader)) {|r|
        if r.key?("content-encoding") and @compression
          @compression = nil # Clear it till next set.
          the_body = r.read_body dest, &block
          case r["content-encoding"]
          when "gzip"
            r.body= Zlib::GzipReader.new(StringIO.new(the_body)).read
            r.delete("content-encoding")
          when "deflate"
            r.body= Zlib::Inflate.inflate(the_body);
            r.delete("content-encoding")
          when "identity"
            ; # nothing needed
          else 
            ; # Don't do anything dramatic, unless we need to later
          end
        else
          r.read_body dest, &block
        end
        res = r
      }
      unless @newimpl
        res.value
        return res, res.body
      end

      res
    end

    # Gets only the header from +path+ on the connected-to host.
    # +header+ is a Hash like { 'Accept' => '*/*', ... }.
    # 
    # This method returns a Net::HTTPResponse object.
    # 
    # In version 1.1, this method might raise an exception for 
    # 3xx (redirect). On the case you can get a HTTPResponse object
    # by "anException.response".
    # In version 1.2, this method never raises an exception.
    # 
    #     response = nil
    #     Net::HTTP.start('some.www.server', 80) {|http|
    #       response = http.head('/index.html')
    #     }
    #     p response['content-type']
    #
    def head(path, initheader = nil) 
      res = request(Head.new(path, initheader))
      res.value unless @newimpl
      res
    end

    # Posts +data+ (must be a String) to +path+. +header+ must be a Hash
    # like { 'Accept' => '*/*', ... }.
    # 
    # In version 1.1 (ruby 1.6), this method returns a pair of objects, a
    # Net::HTTPResponse object and an entity body string.
    # In version 1.2 (ruby 1.8), this method returns a Net::HTTPResponse object.
    # 
    # If called with a block, yields each fragment of the
    # entity body in turn as a string as it are read from
    # the socket.  Note that in this case, the returned response
    # object will *not* contain a (meaningful) body.
    #
    # +dest+ argument is obsolete.
    # It still works but you must not use it.
    # 
    # In version 1.1, this method might raise an exception for 
    # 3xx (redirect). In this case you can get an HTTPResponse object
    # by "anException.response".
    # In version 1.2, this method never raises exception.
    # 
    #     # version 1.1
    #     response, body = http.post('/cgi-bin/search.rb', 'query=foo')
    # 
    #     # version 1.2
    #     response = http.post('/cgi-bin/search.rb', 'query=foo')
    # 
    #     # using block
    #     File.open('result.txt', 'w') {|f|
    #       http.post('/cgi-bin/search.rb', 'query=foo') do |str|
    #         f.write str
    #       end
    #     }
    #
    # You should set Content-Type: header field for POST.
    # If no Content-Type: field given, this method uses
    # "application/x-www-form-urlencoded" by default.
    #
    def post(path, data, initheader = nil, dest = nil, &block) # :yield: +body_segment+
      res = nil
      request(Post.new(path, initheader), data) {|r|
        r.read_body dest, &block
        res = r
      }
      unless @newimpl
        res.value
        return res, res.body
      end
      res
    end

    def put(path, data, initheader = nil)   #:nodoc:
      res = request(Put.new(path, initheader), data)
      res.value unless @newimpl
      res
    end

    def patch(path, data, initheader = nil) #:nodoc:
      res = request(Patch.new(path, initheader), data)
      res.value unless @newimpl
      res
    end

    # Sends a PROPPATCH request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def proppatch(path, body, initheader = nil)
      request(Proppatch.new(path, initheader), body)
    end

    # Sends a LOCK request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def lock(path, body, initheader = nil)
      request(Lock.new(path, initheader), body)
    end

    # Sends a UNLOCK request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def unlock(path, body, initheader = nil)
      request(Unlock.new(path, initheader), body)
    end

    # Sends a OPTIONS request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def options(path, initheader = nil)
      request(Options.new(path, initheader))
    end

    # Sends a PROPFIND request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def propfind(path, body = nil, initheader = {'Depth' => '0'})
      request(Propfind.new(path, initheader), body)
    end

    # Sends a DELETE request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def delete(path, initheader = {'Depth' => 'Infinity'})
      request(Delete.new(path, initheader))
    end

    # Sends a MOVE request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def move(path, initheader = nil)
      request(Move.new(path, initheader))
    end

    # Sends a COPY request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def copy(path, initheader = nil)
      request(Copy.new(path, initheader))
    end

    # Sends a MKCOL request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def mkcol(path, body = nil, initheader = nil)
      request(Mkcol.new(path, initheader), body)
    end

    # Sends a TRACE request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def trace(path, initheader = nil)
      request(Trace.new(path, initheader))
    end

    # Sends a GET request to the +path+ and gets a response,
    # as an HTTPResponse object.
    # 
    # When called with a block, yields an HTTPResponse object.
    # The body of this response will not have been read yet;
    # the caller can process it using HTTPResponse#read_body,
    # if desired.
    #
    # Returns the response.
    # 
    # This method never raises Net::* exceptions.
    # 
    #     response = http.request_get('/index.html')
    #     # The entity body is already read here.
    #     p response['content-type']
    #     puts response.body
    # 
    #     # using block
    #     http.request_get('/index.html') {|response|
    #       p response['content-type']
    #       response.read_body do |str|   # read body now
    #         print str
    #       end
    #     }
    #
    def request_get(path, initheader = nil, &block) # :yield: +response+
      request(Get.new(path, initheader), &block)
    end

    # Sends a HEAD request to the +path+ and gets a response,
    # as an HTTPResponse object.
    #
    # Returns the response.
    # 
    # This method never raises Net::* exceptions.
    # 
    #     response = http.request_head('/index.html')
    #     p response['content-type']
    #
    def request_head(path, initheader = nil, &block)
      request(Head.new(path, initheader), &block)
    end

    # Sends a POST request to the +path+ and gets a response,
    # as an HTTPResponse object.
    # 
    # When called with a block, yields an HTTPResponse object.
    # The body of this response will not have been read yet;
    # the caller can process it using HTTPResponse#read_body,
    # if desired.
    #
    # Returns the response.
    # 
    # This method never raises Net::* exceptions.
    # 
    #     # example
    #     response = http.request_post('/cgi-bin/nice.rb', 'datadatadata...')
    #     p response.status
    #     puts response.body          # body is already read
    # 
    #     # using block
    #     http.request_post('/cgi-bin/nice.rb', 'datadatadata...') {|response|
    #       p response.status
    #       p response['content-type']
    #       response.read_body do |str|   # read body now
    #         print str
    #       end
    #     }
    #
    def request_post(path, data, initheader = nil, &block) # :yield: +response+
      request Post.new(path, initheader), data, &block
    end

    def request_put(path, data, initheader = nil, &block)   #:nodoc:
      request Put.new(path, initheader), data, &block
    end

    alias get2   request_get    #:nodoc: obsolete
    alias head2  request_head   #:nodoc: obsolete
    alias post2  request_post   #:nodoc: obsolete
    alias put2   request_put    #:nodoc: obsolete


    # Sends an HTTP request to the HTTP server.
    # This method also sends DATA string if DATA is given.
    #
    # Returns a HTTPResponse object.
    # 
    # This method never raises Net::* exceptions.
    #
    #    response = http.send_request('GET', '/index.html')
    #    puts response.body
    #
    def send_request(name, path, data = nil, header = nil)
      r = HTTPGenericRequest.new(name,(data ? true : false),true,path,header)
      request r, data
    end

    # Sends an HTTPRequest object REQUEST to the HTTP server.
    # This method also sends DATA string if REQUEST is a post/put request.
    # Giving DATA for get/head request causes ArgumentError.
    # 
    # When called with a block, yields an HTTPResponse object.
    # The body of this response will not have been read yet;
    # the caller can process it using HTTPResponse#read_body,
    # if desired.
    #
    # Returns a HTTPResponse object.
    # 
    # This method never raises Net::* exceptions.
    #
    def request(req, body = nil, &block)  # :yield: +response+
      unless started?
        start {
          req['connection'] ||= 'close'
          return request(req, body, &block)
        }
      end
      if proxy_user()
        req.proxy_basic_auth proxy_user(), proxy_pass() unless use_ssl?
      end
      req.set_body_internal body
      res = transport_request(req, &block)
      if sspi_auth?(res)
        sspi_auth(req)
        res = transport_request(req, &block)
      end
      res
    end

    private

    def transport_request(req)
      begin_transport req
      req.exec @socket, @curr_http_version, edit_path(req.path)
      begin
        res = HTTPResponse.read_new(@socket)
      end while res.kind_of?(HTTPContinue)
      res.reading_body(@socket, req.response_body_permitted?) {
        yield res if block_given?
      }
      end_transport req, res
      res
    end

    def begin_transport(req)
      connect if @socket.closed?
      if not req.response_body_permitted? and @close_on_empty_response
        req['connection'] ||= 'close'
      end
      req['host'] ||= addr_port()
    end

    def end_transport(req, res)
      @curr_http_version = res.http_version
      if @socket.closed?
        D 'Conn socket closed'
      elsif not res.body and @close_on_empty_response
        D 'Conn close'
        @socket.close
      elsif keep_alive?(req, res)
        D 'Conn keep-alive'
      else
        D 'Conn close'
        @socket.close
      end
    end

    def keep_alive?(req, res)
      return false if req.connection_close?
      if @curr_http_version <= '1.0'
        res.connection_keep_alive?
      else   # HTTP/1.1 or later
        not res.connection_close?
      end
    end

    def sspi_auth?(res)
      return false unless @sspi_enabled
      if res.kind_of?(HTTPProxyAuthenticationRequired) and
          proxy? and res["Proxy-Authenticate"].include?("Negotiate")
        begin
          require 'win32/sspi'
          true
        rescue LoadError
          false
        end
      else
        false
      end
    end

    def sspi_auth(req)
      n = Win32::SSPI::NegotiateAuth.new
      req["Proxy-Authorization"] = "Negotiate #{n.get_initial_token}"
      # Some versions of ISA will close the connection if this isn't present.
      req["Connection"] = "Keep-Alive"
      req["Proxy-Connection"] = "Keep-Alive"
      res = transport_request(req)
      authphrase = res["Proxy-Authenticate"]  or return res
      req["Proxy-Authorization"] = "Negotiate #{n.complete_authentication(authphrase)}"
    rescue => err
      raise HTTPAuthenticationError.new('HTTP authentication failed', err)
    end

    #
    # utils
    #

    private

    def addr_port
      if use_ssl?
        address() + (port == HTTP.https_default_port ? '' : ":#{port()}")
      else
        address() + (port == HTTP.http_default_port ? '' : ":#{port()}")
      end
    end

    def D(msg)
      return unless @debug_output
      @debug_output << msg
      @debug_output << "\n"
    end

  end

  HTTPSession = HTTP


  #
  # Header module.
  #
  # Provides access to @header in the mixed-into class as a hash-like
  # object, except with case-insensitive keys.  Also provides
  # methods for accessing commonly-used header values in a more
  # convenient format.
  #
  module HTTPHeader

    def initialize_http_header(initheader)
      @header = {}
      return unless initheader
      initheader.each do |key, value|
        warn "net/http: warning: duplicated HTTP header: #{key}" if key?(key) and $VERBOSE
        @header[key.downcase] = [value.strip]
      end
    end

    def size   #:nodoc: obsolete
      @header.size
    end

    alias length size   #:nodoc: obsolete

    # Returns the header field corresponding to the case-insensitive key.
    # For example, a key of "Content-Type" might return "text/html"
    def [](key)
      a = @header[key.downcase] or return nil
      a.join(', ')
    end

    # Sets the header field corresponding to the case-insensitive key.
    def []=(key, val)
      unless val
        @header.delete key.downcase
        return val
      end
      @header[key.downcase] = [val]
    end

    # [Ruby 1.8.3]
    # Adds header field instead of replace.
    # Second argument +val+ must be a String.
    # See also #[]=, #[] and #get_fields.
    #
    #   request.add_field 'X-My-Header', 'a'
    #   p request['X-My-Header']              #=> "a"
    #   p request.get_fields('X-My-Header')   #=> ["a"]
    #   request.add_field 'X-My-Header', 'b'
    #   p request['X-My-Header']              #=> "a, b"
    #   p request.get_fields('X-My-Header')   #=> ["a", "b"]
    #   request.add_field 'X-My-Header', 'c'
    #   p request['X-My-Header']              #=> "a, b, c"
    #   p request.get_fields('X-My-Header')   #=> ["a", "b", "c"]
    #
    def add_field(key, val)
      if @header.key?(key.downcase)
        @header[key.downcase].push val
      else
        @header[key.downcase] = [val]
      end
    end

    # [Ruby 1.8.3]
    # Returns an array of header field strings corresponding to the
    # case-insensitive +key+.  This method allows you to get duplicated
    # header fields without any processing.  See also #[].
    #
    #   p response.get_fields('Set-Cookie')
    #     #=> ["session=al98axx; expires=Fri, 31-Dec-1999 23:58:23",
    #          "query=rubyscript; expires=Fri, 31-Dec-1999 23:58:23"]
    #   p response['Set-Cookie']
    #     #=> "session=al98axx; expires=Fri, 31-Dec-1999 23:58:23, query=rubyscript; expires=Fri, 31-Dec-1999 23:58:23"
    #
    def get_fields(key)
      return nil unless @header[key.downcase]
      @header[key.downcase].dup
    end

    # Returns the header field corresponding to the case-insensitive key.
    # Returns the default value +args+, or the result of the block, or
    # raises an IndexErrror if there's no header field named +key+
    # See Hash#fetch
    def fetch(key, *args, &block)   #:yield: +key+
      a = @header.fetch(key.downcase, *args, &block)
      a.kind_of?(Array) ? a.join(', ') : a
    end

    # Iterates for each header names and values.
    def each_header   #:yield: +key+, +value+
      @header.each do |k,va|
        yield k, va.join(', ')
      end
    end

    alias each each_header

    # Iterates for each header names.
    def each_name(&block)   #:yield: +key+
      @header.each_key(&block)
    end

    alias each_key each_name

    # Iterates for each capitalized header names.
    def each_capitalized_name(&block)   #:yield: +key+
      @header.each_key do |k|
        yield capitalize(k)
      end
    end

    # Iterates for each header values.
    def each_value   #:yield: +value+
      @header.each_value do |va|
        yield va.join(', ')
      end
    end

    # Removes a header field.
    def delete(key)
      @header.delete(key.downcase)
    end

    # true if +key+ header exists.
    def key?(key)
      @header.key?(key.downcase)
    end

    # Returns a Hash consist of header names and values.
    def to_hash
      @header.dup
    end

    # As for #each_header, except the keys are provided in capitalized form.
    def each_capitalized
      @header.each do |k,v|
        yield capitalize(k), v.join(', ')
      end
    end

    alias canonical_each each_capitalized

    def capitalize(name)
      name.split(/-/).map {|s| s.capitalize }.join('-')
    end
    private :capitalize

    # Returns an Array of Range objects which represents Range: header field,
    # or +nil+ if there is no such header.
    def range
      return nil unless @header['range']
      self['Range'].split(/,/).map {|spec|
        m = /bytes\s*=\s*(\d+)?\s*-\s*(\d+)?/i.match(spec) or
                raise HTTPHeaderSyntaxError, "wrong Range: #{spec}"
        d1 = m[1].to_i
        d2 = m[2].to_i
        if    m[1] and m[2] then  d1..d2
        elsif m[1]          then  d1..-1
        elsif          m[2] then -d2..-1
        else
          raise HTTPHeaderSyntaxError, 'range is not specified'
        end
      }
    end

    # Set Range: header from Range (arg r) or beginning index and
    # length from it (arg idx&len).
    #
    #   req.range = (0..1023)
    #   req.set_range 0, 1023
    #
    def set_range(r, e = nil)
      unless r
        @header.delete 'range'
        return r
      end
      r = (r...r+e) if e
      case r
      when Numeric
        n = r.to_i
        rangestr = (n > 0 ? "0-#{n-1}" : "-#{-n}")
      when Range
        first = r.first
        last = r.last
        last -= 1 if r.exclude_end?
        if last == -1
          rangestr = (first > 0 ? "#{first}-" : "-#{-first}")
        else
          raise HTTPHeaderSyntaxError, 'range.first is negative' if first < 0
          raise HTTPHeaderSyntaxError, 'range.last is negative' if last < 0
          raise HTTPHeaderSyntaxError, 'must be .first < .last' if first > last
          rangestr = "#{first}-#{last}"
        end
      else
        raise TypeError, 'Range/Integer is required'
      end
      @header['range'] = ["bytes=#{rangestr}"]
      r
    end

    alias range= set_range

    # Returns an Integer object which represents the Content-Length: header field
    # or +nil+ if that field is not provided.
    def content_length
      return nil unless key?('Content-Length')
      len = self['Content-Length'].slice(/\d+/) or
          raise HTTPHeaderSyntaxError, 'wrong Content-Length format'
      len.to_i
    end
    
    def content_length=(len)
      unless len
        @header.delete 'content-length'
        return nil
      end
      @header['content-length'] = [len.to_i.to_s]
    end

    # Returns "true" if the "transfer-encoding" header is present and
    # set to "chunked".  This is an HTTP/1.1 feature, allowing the 
    # the content to be sent in "chunks" without at the outset
    # stating the entire content length.
    def chunked?
      return false unless @header['transfer-encoding']
      field = self['Transfer-Encoding']
      (/(?:\A|[^\-\w])chunked(?![\-\w])/i =~ field) ? true : false
    end

    # Returns a Range object which represents Content-Range: header field.
    # This indicates, for a partial entity body, where this fragment
    # fits inside the full entity body, as range of byte offsets.
    def content_range
      return nil unless @header['content-range']
      m = %r<bytes\s+(\d+)-(\d+)/(\d+|\*)>i.match(self['Content-Range']) or
          raise HTTPHeaderSyntaxError, 'wrong Content-Range format'
      m[1].to_i .. m[2].to_i + 1
    end

    # The length of the range represented in Content-Range: header.
    def range_length
      r = content_range() or return nil
      r.end - r.begin
    end

    # Returns a content type string such as "text/html".
    # This method returns nil if Content-Type: header field does not exist.
    def content_type
      return nil unless main_type()
      if sub_type()
      then "#{main_type()}/#{sub_type()}"
      else main_type()
      end
    end

    # Returns a content type string such as "text".
    # This method returns nil if Content-Type: header field does not exist.
    def main_type
      return nil unless @header['content-type']
      self['Content-Type'].split(';').first.to_s.split('/')[0].to_s.strip
    end
    
    # Returns a content type string such as "html".
    # This method returns nil if Content-Type: header field does not exist
    # or sub-type is not given (e.g. "Content-Type: text").
    def sub_type
      return nil unless @header['content-type']
      main, sub = *self['Content-Type'].split(';').first.to_s.split('/')
      return nil unless sub
      sub.strip
    end

    # Returns content type parameters as a Hash as like
    # {"charset" => "iso-2022-jp"}.
    def type_params
      result = {}
      list = self['Content-Type'].to_s.split(';')
      list.shift
      list.each do |param|
        k, v = *param.split('=', 2)
        result[k.strip] = v.strip
      end
      result
    end

    # Set Content-Type: header field by +type+ and +params+.
    # +type+ must be a String, +params+ must be a Hash.
    def set_content_type(type, params = {})
      @header['content-type'] = [type + params.map{|k,v|"; #{k}=#{v}"}.join('')]
    end

    alias content_type= set_content_type

    # Set header fields and a body from HTML form data.
    # +params+ should be a Hash containing HTML form data.
    # Optional argument +sep+ means data record separator.
    #
    # This method also set Content-Type: header field to
    # application/x-www-form-urlencoded.
    #
    # Example:
    #    http.form_data = {"q" => "ruby", "lang" => "en"}
    #    http.form_data = {"q" => ["ruby", "perl"], "lang" => "en"}
    #    http.set_form_data({"q" => "ruby", "lang" => "en"}, ';')
    #    
    def set_form_data(params, sep = '&')
      self.body = params.map {|k, v| encode_kvpair(k, v) }.flatten.join(sep)
      self.content_type = 'application/x-www-form-urlencoded'
    end

    alias form_data= set_form_data

    def encode_kvpair(k, vs)
      Array(vs).map {|v| "#{urlencode(k.to_s)}=#{urlencode(v.to_s)}" }
    end
    private :encode_kvpair

    def urlencode(str)
      str.dup.force_encoding('ASCII-8BIT').gsub(/[^a-zA-Z0-9_\.\-]/){'%%%02x' % $&.ord}
    end
    private :urlencode

    # Set the Authorization: header for "Basic" authorization.
    def basic_auth(account, password)
      @header['authorization'] = [basic_encode(account, password)]
    end

    # Set Proxy-Authorization: header for "Basic" authorization.
    def proxy_basic_auth(account, password)
      @header['proxy-authorization'] = [basic_encode(account, password)]
    end

    def basic_encode(account, password)
      'Basic ' + ["#{account}:#{password}"].pack('m').delete("\r\n")
    end
    private :basic_encode

    def connection_close?
      tokens(@header['connection']).include?('close') or
      tokens(@header['proxy-connection']).include?('close')
    end

    def connection_keep_alive?
      tokens(@header['connection']).include?('keep-alive') or
      tokens(@header['proxy-connection']).include?('keep-alive')
    end

    def tokens(vals)
      return [] unless vals
      vals.map {|v| v.split(',') }.flatten\
          .reject {|str| str.strip.empty? }\
          .map {|tok| tok.strip.downcase }
    end
    private :tokens

  end


  #
  # Parent of HTTPRequest class.  Do not use this directly; use
  # a subclass of HTTPRequest.
  #
  # Mixes in the HTTPHeader module.
  #
  class HTTPGenericRequest

    include HTTPHeader

    def initialize(m, reqbody, resbody, path, initheader = nil)
      @method = m
      @request_has_body = reqbody
      @response_has_body = resbody
      raise ArgumentError, "no HTTP request path given" unless path
      raise ArgumentError, "HTTP request path is empty" if path.empty?
      @path = path
      initialize_http_header initheader
      self['Accept'] ||= '*/*'
      self['User-Agent'] ||= 'Ruby'
      @body = nil
      @body_stream = nil
    end

    attr_reader :method
    attr_reader :path

    def inspect
      "\#<#{self.class} #{@method}>"
    end

    def request_body_permitted?
      @request_has_body
    end

    def response_body_permitted?
      @response_has_body
    end

    def body_exist?
      warn "Net::HTTPRequest#body_exist? is obsolete; use response_body_permitted?" if $VERBOSE
      response_body_permitted?
    end

    attr_reader :body

    def body=(str)
      @body = str
      @body_stream = nil
      str
    end

    attr_reader :body_stream

    def body_stream=(input)
      @body = nil
      @body_stream = input
      input
    end

    def set_body_internal(str)   #:nodoc: internal use only
      raise ArgumentError, "both of body argument and HTTPRequest#body set" if str and (@body or @body_stream)
      self.body = str if str
    end

    #
    # write
    #

    def exec(sock, ver, path)   #:nodoc: internal use only
      if @body
        send_request_with_body sock, ver, path, @body
      elsif @body_stream
        send_request_with_body_stream sock, ver, path, @body_stream
      else
        write_header sock, ver, path
      end
    end

    private

    def send_request_with_body(sock, ver, path, body)
      self.content_length = body.bytesize
      delete 'Transfer-Encoding'
      supply_default_content_type
      write_header sock, ver, path
      sock.write body
    end

    def send_request_with_body_stream(sock, ver, path, f)
      unless content_length() or chunked?
        raise ArgumentError,
            "Content-Length not given and Transfer-Encoding is not `chunked'"
      end
      supply_default_content_type
      write_header sock, ver, path
      if chunked?
        while s = f.read(1024)
          sock.write(sprintf("%x\r\n", s.length) << s << "\r\n")
        end
        sock.write "0\r\n\r\n"
      else
        while s = f.read(1024)
          sock.write s
        end
      end
    end

    def supply_default_content_type
      return if content_type()
      warn 'net/http: warning: Content-Type did not set; using application/x-www-form-urlencoded' if $VERBOSE
      set_content_type 'application/x-www-form-urlencoded'
    end

    def write_header(sock, ver, path)
      buf = "#{@method} #{path} HTTP/#{ver}\r\n"
      each_capitalized do |k,v|
        buf << "#{k}: #{v}\r\n"
      end
      buf << "\r\n"
      sock.write buf
    end
  
  end


  # 
  # HTTP request class. This class wraps request header and entity path.
  # You *must* use its subclass, Net::HTTP::Get, Post, Head.
  # 
  class HTTPRequest < HTTPGenericRequest

    # Creates HTTP request object.
    def initialize(path, initheader = nil)
      super self.class::METHOD,
            self.class::REQUEST_HAS_BODY,
            self.class::RESPONSE_HAS_BODY,
            path, initheader
    end
  end


  class HTTP   # reopen
    #
    # HTTP 1.1 methods --- RFC2616
    #

    class Get < HTTPRequest
      METHOD = 'GET'
      REQUEST_HAS_BODY  = false
      RESPONSE_HAS_BODY = true
    end

    class Head < HTTPRequest
      METHOD = 'HEAD'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = false
    end

    class Post < HTTPRequest
      METHOD = 'POST'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end

    class Put < HTTPRequest
      METHOD = 'PUT'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end

    class Patch < HTTPRequest
      METHOD = 'PATCH'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end

    class Delete < HTTPRequest
      METHOD = 'DELETE'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = true
    end

    class Options < HTTPRequest
      METHOD = 'OPTIONS'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = false
    end

    class Trace < HTTPRequest
      METHOD = 'TRACE'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = true
    end

    #
    # WebDAV methods --- RFC2518
    #

    class Propfind < HTTPRequest
      METHOD = 'PROPFIND'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end

    class Proppatch < HTTPRequest
      METHOD = 'PROPPATCH'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end

    class Mkcol < HTTPRequest
      METHOD = 'MKCOL'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end

    class Copy < HTTPRequest
      METHOD = 'COPY'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = true
    end

    class Move < HTTPRequest
      METHOD = 'MOVE'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = true
    end

    class Lock < HTTPRequest
      METHOD = 'LOCK'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end

    class Unlock < HTTPRequest
      METHOD = 'UNLOCK'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end
  end


  ###
  ### Response
  ###

  # HTTP exception class.
  # You must use its subclasses.
  module HTTPExceptions
    def initialize(msg, res)   #:nodoc:
      super msg
      @response = res
    end
    attr_reader :response
    alias data response    #:nodoc: obsolete
  end
  class HTTPError < ProtocolError
    include HTTPExceptions
  end
  class HTTPRetriableError < ProtoRetriableError
    include HTTPExceptions
  end
  class HTTPServerException < ProtoServerError
    # We cannot use the name "HTTPServerError", it is the name of the response.
    include HTTPExceptions
  end
  class HTTPFatalError < ProtoFatalError
    include HTTPExceptions
  end


  # HTTP response class. This class wraps response header and entity.
  # Mixes in the HTTPHeader module, which provides access to response
  # header values both via hash-like methods and individual readers.
  # Note that each possible HTTP response code defines its own 
  # HTTPResponse subclass.  These are listed below.
  # All classes are
  # defined under the Net module. Indentation indicates inheritance.
  # 
  #   xxx        HTTPResponse
  # 
  #     1xx        HTTPInformation
  #       100        HTTPContinue    
  #       101        HTTPSwitchProtocol
  # 
  #     2xx        HTTPSuccess
  #       200        HTTPOK
  #       201        HTTPCreated
  #       202        HTTPAccepted
  #       203        HTTPNonAuthoritativeInformation
  #       204        HTTPNoContent
  #       205        HTTPResetContent
  #       206        HTTPPartialContent
  # 
  #     3xx        HTTPRedirection
  #       300        HTTPMultipleChoice
  #       301        HTTPMovedPermanently
  #       302        HTTPFound
  #       303        HTTPSeeOther
  #       304        HTTPNotModified
  #       305        HTTPUseProxy
  #       307        HTTPTemporaryRedirect
  # 
  #     4xx        HTTPClientError
  #       400        HTTPBadRequest
  #       401        HTTPUnauthorized
  #       402        HTTPPaymentRequired
  #       403        HTTPForbidden
  #       404        HTTPNotFound
  #       405        HTTPMethodNotAllowed
  #       406        HTTPNotAcceptable
  #       407        HTTPProxyAuthenticationRequired
  #       408        HTTPRequestTimeOut
  #       409        HTTPConflict
  #       410        HTTPGone
  #       411        HTTPLengthRequired
  #       412        HTTPPreconditionFailed
  #       413        HTTPRequestEntityTooLarge
  #       414        HTTPRequestURITooLong
  #       415        HTTPUnsupportedMediaType
  #       416        HTTPRequestedRangeNotSatisfiable
  #       417        HTTPExpectationFailed
  # 
  #     5xx        HTTPServerError
  #       500        HTTPInternalServerError
  #       501        HTTPNotImplemented
  #       502        HTTPBadGateway
  #       503        HTTPServiceUnavailable
  #       504        HTTPGatewayTimeOut
  #       505        HTTPVersionNotSupported
  # 
  #     xxx        HTTPUnknownResponse
  #
  class HTTPResponse
    # true if the response has body.
    def HTTPResponse.body_permitted?
      self::HAS_BODY
    end

    def HTTPResponse.exception_type   # :nodoc: internal use only
      self::EXCEPTION_TYPE
    end
  end   # reopened after

  # :stopdoc:

  class HTTPUnknownResponse < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPError
  end
  class HTTPInformation < HTTPResponse           # 1xx
    HAS_BODY = false
    EXCEPTION_TYPE = HTTPError
  end
  class HTTPSuccess < HTTPResponse               # 2xx
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPError
  end
  class HTTPRedirection < HTTPResponse           # 3xx
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPRetriableError
  end
  class HTTPClientError < HTTPResponse           # 4xx
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPServerException   # for backward compatibility
  end
  class HTTPServerError < HTTPResponse           # 5xx
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPFatalError    # for backward compatibility
  end

  class HTTPContinue < HTTPInformation           # 100
    HAS_BODY = false
  end
  class HTTPSwitchProtocol < HTTPInformation     # 101
    HAS_BODY = false
  end

  class HTTPOK < HTTPSuccess                            # 200
    HAS_BODY = true
  end
  class HTTPCreated < HTTPSuccess                       # 201
    HAS_BODY = true
  end
  class HTTPAccepted < HTTPSuccess                      # 202
    HAS_BODY = true
  end
  class HTTPNonAuthoritativeInformation < HTTPSuccess   # 203
    HAS_BODY = true
  end
  class HTTPNoContent < HTTPSuccess                     # 204
    HAS_BODY = false
  end
  class HTTPResetContent < HTTPSuccess                  # 205
    HAS_BODY = false
  end
  class HTTPPartialContent < HTTPSuccess                # 206
    HAS_BODY = true
  end

  class HTTPMultipleChoice < HTTPRedirection     # 300
    HAS_BODY = true
  end
  class HTTPMovedPermanently < HTTPRedirection   # 301
    HAS_BODY = true
  end
  class HTTPFound < HTTPRedirection              # 302
    HAS_BODY = true
  end
  HTTPMovedTemporarily = HTTPFound
  class HTTPSeeOther < HTTPRedirection           # 303
    HAS_BODY = true
  end
  class HTTPNotModified < HTTPRedirection        # 304
    HAS_BODY = false
  end
  class HTTPUseProxy < HTTPRedirection           # 305
    HAS_BODY = false
  end
  # 306 unused
  class HTTPTemporaryRedirect < HTTPRedirection  # 307
    HAS_BODY = true
  end

  class HTTPBadRequest < HTTPClientError                    # 400
    HAS_BODY = true
  end
  class HTTPUnauthorized < HTTPClientError                  # 401
    HAS_BODY = true
  end
  class HTTPPaymentRequired < HTTPClientError               # 402
    HAS_BODY = true
  end
  class HTTPForbidden < HTTPClientError                     # 403
    HAS_BODY = true
  end
  class HTTPNotFound < HTTPClientError                      # 404
    HAS_BODY = true
  end
  class HTTPMethodNotAllowed < HTTPClientError              # 405
    HAS_BODY = true
  end
  class HTTPNotAcceptable < HTTPClientError                 # 406
    HAS_BODY = true
  end
  class HTTPProxyAuthenticationRequired < HTTPClientError   # 407
    HAS_BODY = true
  end
  class HTTPRequestTimeOut < HTTPClientError                # 408
    HAS_BODY = true
  end
  class HTTPConflict < HTTPClientError                      # 409
    HAS_BODY = true
  end
  class HTTPGone < HTTPClientError                          # 410
    HAS_BODY = true
  end
  class HTTPLengthRequired < HTTPClientError                # 411
    HAS_BODY = true
  end
  class HTTPPreconditionFailed < HTTPClientError            # 412
    HAS_BODY = true
  end
  class HTTPRequestEntityTooLarge < HTTPClientError         # 413
    HAS_BODY = true
  end
  class HTTPRequestURITooLong < HTTPClientError             # 414
    HAS_BODY = true
  end
  HTTPRequestURITooLarge = HTTPRequestURITooLong
  class HTTPUnsupportedMediaType < HTTPClientError          # 415
    HAS_BODY = true
  end
  class HTTPRequestedRangeNotSatisfiable < HTTPClientError  # 416
    HAS_BODY = true
  end
  class HTTPExpectationFailed < HTTPClientError             # 417
    HAS_BODY = true
  end

  class HTTPInternalServerError < HTTPServerError   # 500
    HAS_BODY = true
  end
  class HTTPNotImplemented < HTTPServerError        # 501
    HAS_BODY = true
  end
  class HTTPBadGateway < HTTPServerError            # 502
    HAS_BODY = true
  end
  class HTTPServiceUnavailable < HTTPServerError    # 503
    HAS_BODY = true
  end
  class HTTPGatewayTimeOut < HTTPServerError        # 504
    HAS_BODY = true
  end
  class HTTPVersionNotSupported < HTTPServerError   # 505
    HAS_BODY = true
  end

  # :startdoc:


  class HTTPResponse   # reopen

    CODE_CLASS_TO_OBJ = {
      '1' => HTTPInformation,
      '2' => HTTPSuccess,
      '3' => HTTPRedirection,
      '4' => HTTPClientError,
      '5' => HTTPServerError
    }
    CODE_TO_OBJ = {
      '100' => HTTPContinue,
      '101' => HTTPSwitchProtocol,

      '200' => HTTPOK,
      '201' => HTTPCreated,
      '202' => HTTPAccepted,
      '203' => HTTPNonAuthoritativeInformation,
      '204' => HTTPNoContent,
      '205' => HTTPResetContent,
      '206' => HTTPPartialContent,

      '300' => HTTPMultipleChoice,
      '301' => HTTPMovedPermanently,
      '302' => HTTPFound,
      '303' => HTTPSeeOther,
      '304' => HTTPNotModified,
      '305' => HTTPUseProxy,
      '307' => HTTPTemporaryRedirect,

      '400' => HTTPBadRequest,
      '401' => HTTPUnauthorized,
      '402' => HTTPPaymentRequired,
      '403' => HTTPForbidden,
      '404' => HTTPNotFound,
      '405' => HTTPMethodNotAllowed,
      '406' => HTTPNotAcceptable,
      '407' => HTTPProxyAuthenticationRequired,
      '408' => HTTPRequestTimeOut,
      '409' => HTTPConflict,
      '410' => HTTPGone,
      '411' => HTTPLengthRequired,
      '412' => HTTPPreconditionFailed,
      '413' => HTTPRequestEntityTooLarge,
      '414' => HTTPRequestURITooLong,
      '415' => HTTPUnsupportedMediaType,
      '416' => HTTPRequestedRangeNotSatisfiable,
      '417' => HTTPExpectationFailed,

      '500' => HTTPInternalServerError,
      '501' => HTTPNotImplemented,
      '502' => HTTPBadGateway,
      '503' => HTTPServiceUnavailable,
      '504' => HTTPGatewayTimeOut,
      '505' => HTTPVersionNotSupported
    }

    class << HTTPResponse
      def read_new(sock)   #:nodoc: internal use only
        httpv, code, msg = read_status_line(sock)
        res = response_class(code).new(httpv, code, msg)
        each_response_header(sock) do |k,v|
          res.add_field k, v
        end
        res
      end

      private

      def read_status_line(sock)
        str = sock.readline
        m = /\AHTTP(?:\/(\d+\.\d+))?\s+(\d\d\d)\s*(.*)\z/in.match(str) or
          raise HTTPBadResponse, "wrong status line: #{str.dump}"
        m.captures
      end

      def response_class(code)
        CODE_TO_OBJ[code] or
        CODE_CLASS_TO_OBJ[code[0,1]] or
        HTTPUnknownResponse
      end

      def each_response_header(sock)
        key = value = nil
        while true
          line = sock.readuntil("\n", true).sub(/\s+\z/, '')
          break if line.empty?
          if line[0] == ?\s or line[0] == ?\t and value
            value << ' ' unless value.empty?
            value << line.strip
          else
            yield key, value if key
            key, value = line.strip.split(/\s*:\s*/, 2)
            raise HTTPBadResponse, 'wrong header line format' if value.nil?
          end
        end
        yield key, value if key
      end
    end

    # next is to fix bug in RDoc, where the private inside class << self
    # spills out.
    public 

    include HTTPHeader

    def initialize(httpv, code, msg)   #:nodoc: internal use only
      @http_version = httpv
      @code         = code
      @message      = msg
      initialize_http_header nil
      @body = nil
      @read = false
    end

    # The HTTP version supported by the server.
    attr_reader :http_version

    # HTTP result code string. For example, '302'.  You can also
    # determine the response type by which response subclass the
    # response object is an instance of.
    attr_reader :code

    # HTTP result message. For example, 'Not Found'.
    attr_reader :message
    alias msg message   # :nodoc: obsolete

    def inspect
      "#<#{self.class} #{@code} #{@message} readbody=#{@read}>"
    end

    # For backward compatibility.
    # To allow Net::HTTP 1.1 style assignment
    # e.g.
    #    response, body = Net::HTTP.get(....)
    # 
    def to_ary
      warn "net/http.rb: warning: Net::HTTP v1.1 style assignment found at #{caller(1)[0]}; use `response = http.get(...)' instead." if $VERBOSE
      res = self.dup
      class << res
        undef to_ary
      end
      [res, res.body]
    end

    #
    # response <-> exception relationship
    #

    def code_type   #:nodoc:
      self.class
    end

    def error!   #:nodoc:
      raise error_type().new(@code + ' ' + @message.dump, self)
    end

    def error_type   #:nodoc:
      self.class::EXCEPTION_TYPE
    end

    # Raises HTTP error if the response is not 2xx.
    def value
      error! unless self.kind_of?(HTTPSuccess)
    end

    #
    # header (for backward compatibility only; DO NOT USE)
    #

    def response   #:nodoc:
      warn "#{caller(1)[0]}: warning: HTTPResponse#response is obsolete" if $VERBOSE
      self
    end

    def header   #:nodoc:
      warn "#{caller(1)[0]}: warning: HTTPResponse#header is obsolete" if $VERBOSE
      self
    end

    def read_header   #:nodoc:
      warn "#{caller(1)[0]}: warning: HTTPResponse#read_header is obsolete" if $VERBOSE
      self
    end

    #
    # body
    #

    def reading_body(sock, reqmethodallowbody)  #:nodoc: internal use only
      @socket = sock
      @body_exist = reqmethodallowbody && self.class.body_permitted?
      begin
        yield
        self.body   # ensure to read body
      ensure
        @socket = nil
      end
    end

    # Gets entity body.  If the block given, yields it to +block+.
    # The body is provided in fragments, as it is read in from the socket.
    #
    # Calling this method a second or subsequent time will return the
    # already read string.
    #
    #   http.request_get('/index.html') {|res|
    #     puts res.read_body
    #   }
    #
    #   http.request_get('/index.html') {|res|
    #     p res.read_body.object_id   # 538149362
    #     p res.read_body.object_id   # 538149362
    #   }
    #
    #   # using iterator
    #   http.request_get('/index.html') {|res|
    #     res.read_body do |segment|
    #       print segment
    #     end
    #   }
    #
    def read_body(dest = nil, &block)
      if @read
        raise IOError, "#{self.class}\#read_body called twice" if dest or block
        return @body
      end
      to = procdest(dest, block)
      stream_check
      if @body_exist
        read_body_0 to
        @body = to
      else
        @body = nil
      end
      @read = true

      @body
    end

    # Returns the entity body.
    #
    # Calling this method a second or subsequent time will return the
    # already read string.
    #
    #   http.request_get('/index.html') {|res|
    #     puts res.body
    #   }
    #
    #   http.request_get('/index.html') {|res|
    #     p res.body.object_id   # 538149362
    #     p res.body.object_id   # 538149362
    #   }
    #
    def body
      read_body()
    end

    # Because it may be necessary to modify the body, Eg, decompression
    # this method facilitates that.
    def body=(value)
      @body = value
    end

    alias entity body   #:nodoc: obsolete

    private

    def read_body_0(dest)
      if chunked?
        read_chunked dest
        return
      end
      clen = content_length()
      if clen
        @socket.read clen, dest, true   # ignore EOF
        return
      end
      clen = range_length()
      if clen
        @socket.read clen, dest
        return
      end
      @socket.read_all dest
    end

    def read_chunked(dest)
      len = nil
      total = 0
      while true
        line = @socket.readline
        hexlen = line.slice(/[0-9a-fA-F]+/) or
            raise HTTPBadResponse, "wrong chunk size line: #{line}"
        len = hexlen.hex
        break if len == 0
        @socket.read len, dest; total += len
        @socket.read 2   # \r\n
      end
      until @socket.readline.empty?
        # none
      end
    end

    def stream_check
      raise IOError, 'attempt to read body out of block' if @socket.closed?
    end

    def procdest(dest, block)
      raise ArgumentError, 'both arg and block given for HTTP method' \
          if dest and block
      if block
        ReadAdapter.new(block)
      else
        dest || ''
      end
    end

  end


  # :enddoc:

  #--
  # for backward compatibility
  class HTTP
    ProxyMod = ProxyDelta
  end
  module NetPrivate
    HTTPRequest = ::Net::HTTPRequest
  end

  HTTPInformationCode = HTTPInformation
  HTTPSuccessCode     = HTTPSuccess
  HTTPRedirectionCode = HTTPRedirection
  HTTPRetriableCode   = HTTPRedirection
  HTTPClientErrorCode = HTTPClientError
  HTTPFatalErrorCode  = HTTPClientError
  HTTPServerErrorCode = HTTPServerError
  HTTPResponceReceiver = HTTPResponse

end   # module Net
