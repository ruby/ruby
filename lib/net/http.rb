=begin

= net/http.rb version 1.1.37

Copyright (c) 1999-2001 Yukihiro Matsumoto

written & maintained by Minero Aoki <aamine@loveruby.net>
This file is derived from "http-access.rb".

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.

NOTE: You can find Japanese version of this document in
the doc/net directory of the standard ruby interpreter package.

== What is this module?

This module provide your program the functions to access WWW
documents via HTTP, Hyper Text Transfer Protocol version 1.1.
For details of HTTP, refer [RFC2616]
((<URL:http://www.ietf.org/rfc/rfc2616.txt>)).

== Examples

=== Getting Document From Server

Be care to ',' (comma) putted after "response".
This is required for compatibility.

    require 'net/http'
    Net::HTTP.start( 'some.www.server', 80 ) {|http|
      response , = http.get('/index.html')
      puts response.body
    }

(shorter version)

    require 'net/http'
    Net::HTTP.get_print 'some.www.server', '/index.html'

=== Posting Form Data

    require 'net/http'
    Net::HTTP.start( 'some.www.server', 80 ) {|http|
        response , = http.post( '/cgi-bin/any.rhtml',
                                'querytype=subject&target=ruby' )
    }

=== Accessing via Proxy

Net::HTTP.Proxy() creates http proxy class. It has same
methods of Net::HTTP but its instances always connect to
proxy, instead of given host.

    require 'net/http'

    $proxy_addr = 'your.proxy.addr'
    $proxy_port = 8080
          :
    Net::HTTP::Proxy($proxy_addr, $proxy_port).start( 'some.www.server' ) {|http|
      # always connect to your.proxy.addr:8080
          :
    }

Since Net::HTTP.Proxy() returns Net::HTTP itself when $proxy_addr is nil,
there's no need to change code if there's proxy or not.

=== Redirect

    require 'net/http'
    Net::HTTP.version_1_1

    host = 'www.ruby-lang.org'
    path = '/'
    begin
      Net::HTTP.start( host, 80 ) {|http|
	response , = http.get(path)
        print response.body
      }
    rescue Net::ProtoRetriableError => err
      if m = %r<http://([^/]+)>.match( err.response['location'] ) then
	host = m[1].strip
	path = m.post_match
	retry
      end
    end

NOTE: This code is using ad-hoc way to extract host name, but in future
URI class will be included in ruby standard library.

=== Basic Authentication

    require 'net/http'

    Net::HTTP.start( 'auth.some.domain' ) {|http|
        response , = http.get( '/need-auth.cgi',
                'Authentication' => ["#{account}:#{password}"].pack('m').strip )
        print response.body
    }

In version 1.2 (Ruby 1.7 or later), you can write like this:

    require 'net/http'

    req = Net::HTTP::Get.new('/need-auth.cgi')
    req.basic_auth 'account', 'password'
    Net::HTTP.start( 'auth.some.domain' ) {|http|
        response = http.request(req)
        print response.body
    }

== Switching Net::HTTP versions

You can use old Net::HTTP (in Ruby 1.6) features by calling
HTTP.version_1_1. And calling Net::HTTP.version_1_2 allows
you to use 1.2 features again.

    # example
    Net::HTTP.start {|http1| ...(http1 has 1.2 features)... }

    Net::HTTP.version_1_1
    Net::HTTP.start {|http2| ...(http2 has 1.1 features)... }

    Net::HTTP.version_1_2
    Net::HTTP.start {|http3| ...(http3 has 1.2 features)... }

Yes, this is not thread-safe.

== class Net::HTTP

=== Class Methods

: new( address, port = 80, proxy_addr = nil, proxy_port = nil )
    creates a new Net::HTTP object.
    If proxy_addr is given, creates an Net::HTTP object with proxy support.

: start( address, port = 80, proxy_addr = nil, proxy_port = nil )
: start( address, port = 80, proxy_addr = nil, proxy_port = nil ) {|http| .... }
    is equals to

        Net::HTTP.new(address, port, proxy_addr, proxy_port).start(&block)

: get( address, path, port = 80 )
    gets entity body from path and returns it.
    return value is a String.

: get_print( address, path, port = 80 )
    gets entity body from path and output it to $stdout.

: Proxy( address, port = 80 )
    creates a HTTP proxy class.
    Arguments are address/port of proxy host.
    You can replace HTTP class with created proxy class.

    If ADDRESS is nil, this method returns self (Net::HTTP).

        # example
        proxy_class = Net::HTTP::Proxy( 'proxy.foo.org', 8080 )
                        :
        proxy_class.start( 'www.ruby-lang.org' ) {|http|
            # connecting proxy.foo.org:8080
                        :
        }

: proxy_class?
    If self is HTTP, false.
    If self is a class which was created by HTTP::Proxy(), true.

: port
    default HTTP port (80).

=== Instance Methods

: start
: start {|http| .... }
    creates a new Net::HTTP object and starts HTTP session.

    When this method is called with block, gives a HTTP object to block
    and close the HTTP session after block call finished.

: active?
    true if HTTP session is started.

: address
    the address to connect

: port
    the port number to connect

: open_timeout
: open_timeout=(n)
    seconds to wait until connection is opened.
    If HTTP object cannot open a conection in this seconds,
    it raises TimeoutError exception.

: read_timeout
: read_timeout=(n)
    seconds to wait until reading one block (by one read(1) call).
    If HTTP object cannot open a conection in this seconds,
    it raises TimeoutError exception.

: finish
    finishes HTTP session.
    If HTTP session had not started, raises an IOError.

: proxy?
    true if self is a HTTP proxy class

: proxy_address
    address of proxy host. If self does not use a proxy, nil.

: proxy_port
    port number of proxy host. If self does not use a proxy, nil.

: get( path, header = nil, dest = '' )
: get( path, header = nil ) {|str| .... }
    gets data from PATH on the connecting host.
    HEADER must be a Hash like { 'Accept' => '*/*', ... }.
    Response body is written into DEST by using "<<" method.

    This method returns Net::HTTPResponse object.

    If called with block, gives entity body little by little
    to the block (as String).

    In version 1.1, this method might raises exception for also
    3xx (redirect). On the case you can get a HTTPResponse object
    by "anException.response".

    In version 1.2, this method never raises exception.

        # version 1.1 (bundled with Ruby 1.6)
        response, body = http.get( '/index.html' )

        # version 1.2 (bundled with Ruby 1.7 or later)
        response = http.get( '/index.html' )

        # compatible in both version
        response , = http.get( '/index.html' )
        response.body
        
        # using block
        File.open( 'save.txt', 'w' ) {|f|
            http.get( '/~foo/', nil ) do |str|
              f.write str
            end
        }
        # same effect
        File.open( 'save.txt', 'w' ) {|f|
            http.get '/~foo/', nil, f
        }

: head( path, header = nil )
    gets only header from PATH on the connecting host.
    HEADER is a Hash like { 'Accept' => '*/*', ... }.

    This method returns a Net::HTTPResponse object.

    In version 1.1, this method might raises exception for also
    3xx (redirect). On the case you can get a HTTPResponse object
    by "anException.response".

        response = nil
        Net::HTTP.start( 'some.www.server', 80 ) {|http|
            response = http.head( '/index.html' )
        }
        p response['content-type']

: post( path, data, header = nil, dest = '' )
: post( path, data, header = nil ) {|str| .... }
    posts "data" (must be String) to "path".
    If the body exists, also gets entity body.
    Response body is written into "dest" by using "<<" method.
    "header" must be a Hash like { 'Accept' => '*/*', ... }.
    This method returns Net::HTTPResponse object.

    If called with block, gives a part of entity body string.

    In version 1.1, this method might raises exception for also
    3xx (redirect). On the case you can get a HTTPResponse object
    by "anException.response".

        # version 1.1
        response, body = http.post( '/cgi-bin/search.rb', 'querytype=subject&target=ruby' )
        # version 1.2
        response = http.post( '/cgi-bin/search.rb', 'querytype=subject&target=ruby' )
        # compatible for both version
        response , = http.post( '/cgi-bin/search.rb', 'querytype=subject&target=ruby' )

        # using block
        File.open( 'save.html', 'w' ) {|f|
            http.post( '/cgi-bin/search.rb', 'querytype=subject&target=ruby' ) do |str|
              f.write str
            end
        }
        # same effect
        File.open( 'save.html', 'w' ) {|f|
            http.post '/cgi-bin/search.rb', 'querytype=subject&target=ruby', nil, f
        }

: get2( path, header = nil )
: get2( path, header = nil ) {|response| .... }
    gets entity from PATH. This method returns a HTTPResponse object.

    When called with block, keep connection while block is executed
    and gives a HTTPResponse object to the block.

    This method never raise any ProtocolErrors.

        # example
        response = http.get2( '/index.html' )
        p response['content-type']
        puts response.body          # body is already read

        # using block
        http.get2( '/index.html' ) {|response|
            p response['content-type']
            response.read_body do |str|   # read body now
              print str
            end
        }

: post2( path, header = nil )
: post2( path, header = nil ) {|response| .... }
    posts data to PATH. This method returns a HTTPResponse object.

    When called with block, gives a HTTPResponse object to the block
    before reading entity body, with keeping connection.

        # example
        response = http.post2( '/cgi-bin/nice.rb', 'datadatadata...' )
        p response.status
        puts response.body          # body is already read

        # using block
        http.post2( '/cgi-bin/nice.rb', 'datadatadata...' ) {|response|
            p response.status
            p response['content-type']
            response.read_body do |str|   # read body now
              print str
	    end
        }


== class Net::HTTPResponse

HTTP response class. This class wraps response header and entity.
All arguments named KEY is case-insensitive.

=== Instance Methods

: self[ key ]
    returns the header field corresponding to the case-insensitive key.
    For example, a key of "Content-Type" might return "text/html".
    A key of "Content-Length" might do "2045".

    More than one fields which has same names are joined with ','.

: self[ key ] = val
    sets the header field corresponding to the case-insensitive key.

: key?( key )
    true if key exists.
    KEY is case insensitive.

: each {|name,value| .... }
    iterates for each field name and value pair.

: canonical_each {|name,value| .... }
    iterates for each "canonical" field name and value pair.

: code
    HTTP result code string. For example, '302'.

: message
    HTTP result message. For example, 'Not Found'.

: read_body( dest = '' )
    gets entity body and write it into DEST using "<<" method.
    If this method is called twice or more, nothing will be done
    and returns first DEST.

: read_body {|str| .... }
    gets entity body little by little and pass it to block.

: body
    response body. If #read_body has been called, this method returns
    arg of #read_body DEST. Else gets body as String and returns it.

=end

require 'net/protocol'


module Net

  class HTTPBadResponse < StandardError; end
  class HTTPHeaderSyntaxError < StandardError; end


  class HTTP < Protocol

    HTTPVersion = '1.1'

    #
    # connection
    #

    protocol_param :port, '80'

    def initialize( addr, port = nil )
      super

      @curr_http_version = HTTPVersion
      @seems_1_0_server = false
    end

    private

    def conn_command( sock )
    end

    def do_finish
    end


    #
    # proxy
    #

    public


    class << self

      def Proxy( p_addr, p_port = nil )
        if p_addr then
          ProxyMod.create_proxy_class( p_addr, p_port || self.port )
        else
          self
        end
      end

      alias orig_new new

      def new( address, port = nil, p_addr = nil, p_port = nil )
        c = p_addr ? self::Proxy(p_addr, p_port) : self
        i = c.orig_new( address, port )
        setvar i
        i
      end

      def start( address, port = nil, p_addr = nil, p_port = nil, &block )
        new( address, port, p_addr, p_port ).start( &block )
      end

      @is_proxy_class = false
      @proxy_addr = nil
      @proxy_port = nil

      def proxy_class?
        @is_proxy_class
      end

      attr_reader :proxy_address
      attr_reader :proxy_port

    end

    def proxy?
      type.proxy_class?
    end

    def proxy_address
      type.proxy_address
    end

    def proxy_port
      type.proxy_port
    end

    alias proxyaddr proxy_address
    alias proxyport proxy_port

    def edit_path( path )
      path
    end


    module ProxyMod

      def self.create_proxy_class( p_addr, p_port )
        mod = self
        klass = Class.new( HTTP )
        klass.module_eval {
          include mod
          @is_proxy_class = true
          @proxy_address = p_addr
          @proxy_port    = p_port
        }
        klass
      end

      private
    
      def conn_socket( addr, port )
        super proxy_address, proxy_port
      end

      def edit_path( path )
        'http://' + addr_port + path
      end
    
    end   # module ProxyMod


    #
    # for backward compatibility
    #

    if Version < '1.2.0' then   ###noupdate
      @@newimpl = false
    else
      @@newimpl = true
    end

    class << self

      def version_1_2
        @@newimpl = true
      end

      def version_1_1
        @@newimpl = false
      end

      def is_version_1_2?
        @@newimpl
      end

      private

      def setvar( obj )
        f = @@newimpl
        obj.instance_eval { @newimpl = f }
      end

    end


    #
    # http operations
    #

    public

    def self.define_http_method_interface( nm, hasdest, hasdata )
      name = nm.id2name.downcase
      cname = nm.id2name
      lineno = __LINE__ + 2
      src = <<"      ----"

        def #{name}( path, #{hasdata ? 'data,' : ''}
                     u_header = nil #{hasdest ? ',dest = nil, &block' : ''} )
          resp = nil
          request(
              #{cname}.new( path, u_header ) #{hasdata ? ',data' : ''}
          ) do |resp|
            resp.read_body( #{hasdest ? 'dest, &block' : ''} )
          end
          if @newimpl then
            resp
          else
            resp.value
            #{hasdest ? 'return resp, resp.body' : 'resp'}
          end
        end

        def #{name}2( path, #{hasdata ? 'data,' : ''}
                      u_header = nil, &block )
          request( #{cname}.new(path, u_header),
                   #{hasdata ? 'data,' : ''} &block )
        end
      ----
      module_eval src, __FILE__, lineno
    end

    define_http_method_interface :Get,  true,  false
    define_http_method_interface :Head, false, false
    define_http_method_interface :Post, true,  true
    define_http_method_interface :Put,  false, true

    def request( req, body = nil, &block )
      unless active? then
        start {
          req['connection'] = 'close'
          return request(req, body, &block)
        }
      end
        
      connecting( req ) {
        req.__send__( :exec,
                @socket, @curr_http_version, edit_path(req.path), body )
        yield req.response if block_given?
      }
      req.response
    end

    def send_request( name, path, body = nil, header = nil )
      r = ::Net::NetPrivate::HTTPGenericRequest.new(
              name, (body ? true : false), true,
              path, header )
      request r, body
    end


    private


    def connecting( req )
      if @socket.closed? then
        re_connect
      end
      if not req.body_exist? or @seems_1_0_server then
        req['connection'] = 'close'
      end
      req['host'] = addr_port()

      yield req
      req.response.__send__ :terminate
      @curr_http_version = req.response.http_version

      if not req.response.body then
        @socket.close
      elsif keep_alive? req, req.response then
        D 'Conn keep-alive'
        if @socket.closed? then   # (only) read stream had been closed
          D 'Conn (but seems 1.0 server)'
          @seems_1_0_server = true
          @socket.close
        end
      else
        D 'Conn close'
        @socket.close
      end
    end

    def keep_alive?( req, res )
      /close/i === req['connection'].to_s            and return false
      @seems_1_0_server                              and return false

      /keep-alive/i === res['connection'].to_s       and return true
      /close/i      === res['connection'].to_s       and return false
      /keep-alive/i === res['proxy-connection'].to_s and return true
      /close/i      === res['proxy-connection'].to_s and return false

      @curr_http_version == '1.1'                    and return true
      false
    end


    #
    # utils
    #

    public

    def self.get( addr, path, port = nil )
      req = Get.new( path )
      resp = nil
      new( addr, port || HTTP.port ).start {|http|
        resp = http.request( req )
      }
      resp.body
    end

    def self.get_print( addr, path, port = nil )
      new( addr, port || HTTP.port ).start {|http|
        http.get path, nil, $stdout
      }
      nil
    end


    private

    def addr_port
      address + (port == HTTP.port ? '' : ":#{port}")
    end

    def D( msg )
      if @dout then
        @dout << msg
        @dout << "\n"
      end
    end

  end

  HTTPSession = HTTP



  class Code

    def http_mkchild( bodyexist = nil )
      c = mkchild(nil)
      be = if bodyexist.nil? then @body_exist else bodyexist end
      c.instance_eval { @body_exist = be }
      c
    end

    def body_exist?
      @body_exist
    end
  
  end

  HTTPInformationCode               = InformationCode.http_mkchild( false )
  HTTPSuccessCode                   = SuccessCode    .http_mkchild( true )
  HTTPRedirectionCode               = RetriableCode  .http_mkchild( true )
  HTTPRetriableCode = HTTPRedirectionCode
  HTTPClientErrorCode               = FatalErrorCode .http_mkchild( true )
  HTTPFatalErrorCode = HTTPClientErrorCode
  HTTPServerErrorCode               = ServerErrorCode.http_mkchild( true )


  HTTPSwitchProtocol                = HTTPInformationCode.http_mkchild

  HTTPOK                            = HTTPSuccessCode.http_mkchild
  HTTPCreated                       = HTTPSuccessCode.http_mkchild
  HTTPAccepted                      = HTTPSuccessCode.http_mkchild
  HTTPNonAuthoritativeInformation   = HTTPSuccessCode.http_mkchild
  HTTPNoContent                     = HTTPSuccessCode.http_mkchild( false )
  HTTPResetContent                  = HTTPSuccessCode.http_mkchild( false )
  HTTPPartialContent                = HTTPSuccessCode.http_mkchild

  HTTPMultipleChoice                = HTTPRedirectionCode.http_mkchild
  HTTPMovedPermanently              = HTTPRedirectionCode.http_mkchild
  HTTPMovedTemporarily              = HTTPRedirectionCode.http_mkchild
  HTTPNotModified                   = HTTPRedirectionCode.http_mkchild( false )
  HTTPUseProxy                      = HTTPRedirectionCode.http_mkchild( false )
  
  HTTPBadRequest                    = HTTPClientErrorCode.http_mkchild
  HTTPUnauthorized                  = HTTPClientErrorCode.http_mkchild
  HTTPPaymentRequired               = HTTPClientErrorCode.http_mkchild
  HTTPForbidden                     = HTTPClientErrorCode.http_mkchild
  HTTPNotFound                      = HTTPClientErrorCode.http_mkchild
  HTTPMethodNotAllowed              = HTTPClientErrorCode.http_mkchild
  HTTPNotAcceptable                 = HTTPClientErrorCode.http_mkchild
  HTTPProxyAuthenticationRequired   = HTTPClientErrorCode.http_mkchild
  HTTPRequestTimeOut                = HTTPClientErrorCode.http_mkchild
  HTTPConflict                      = HTTPClientErrorCode.http_mkchild
  HTTPGone                          = HTTPClientErrorCode.http_mkchild
  HTTPLengthRequired                = HTTPClientErrorCode.http_mkchild
  HTTPPreconditionFailed            = HTTPClientErrorCode.http_mkchild
  HTTPRequestEntityTooLarge         = HTTPClientErrorCode.http_mkchild
  HTTPRequestURITooLarge            = HTTPClientErrorCode.http_mkchild
  HTTPUnsupportedMediaType          = HTTPClientErrorCode.http_mkchild

  HTTPNotImplemented                = HTTPServerErrorCode.http_mkchild
  HTTPBadGateway                    = HTTPServerErrorCode.http_mkchild
  HTTPServiceUnavailable            = HTTPServerErrorCode.http_mkchild
  HTTPGatewayTimeOut                = HTTPServerErrorCode.http_mkchild
  HTTPVersionNotSupported           = HTTPServerErrorCode.http_mkchild



  ###
  ### header
  ###

  net_private {

  module HTTPHeader

    def size
      @header.size
    end

    alias length size

    def []( key )
      @header[ key.downcase ]
    end

    def []=( key, val )
      @header[ key.downcase ] = val
    end

    def each( &block )
      @header.each( &block )
    end

    def each_key( &block )
      @header.each_key( &block )
    end

    def each_value( &block )
      @header.each_value( &block )
    end

    def delete( key )
      @header.delete key.downcase
    end

    def key?( key )
      @header.key? key.downcase
    end

    def to_hash
      @header.dup
    end

    def canonical_each
      @header.each do |k,v|
        yield canonical(k), v
      end
    end

    def canonical( k )
      k.split('-').collect {|i| i.capitalize }.join('-')
    end

    def range
      s = @header['range']
      s or return nil

      arr = []
      s.split(',').each do |spec|
        m = /bytes\s*=\s*(\d+)?\s*-\s*(\d+)?/i.match( spec )
        m or raise HTTPHeaderSyntaxError, "wrong Range: #{spec}"

        d1 = m[1].to_i
        d2 = m[2].to_i
        if    m[1] and m[2] then arr.push(  d1..d2 )
        elsif m[1]          then arr.push(  d1..-1 )
        elsif          m[2] then arr.push( -d2..-1 )
        else
          raise HTTPHeaderSyntaxError, 'range is not specified'
        end
      end

      return arr
    end

    def range=( r, fin = nil )
      if fin then
        r = r ... r+fin
      end

      case r
      when Numeric
        s = r > 0 ? "0-#{r - 1}" : "-#{-r}"
      when Range
        first = r.first
        last = r.last
        if r.exclude_end? then
          last -= 1
        end

        if last == -1 then
          s = first > 0 ? "#{first}-" : "-#{-first}"
        else
          first >= 0 or raise HTTPHeaderSyntaxError, 'range.first is negative' 
          last > 0  or raise HTTPHeaderSyntaxError, 'range.last is negative' 
          first < last or raise HTTPHeaderSyntaxError, 'must be .first < .last'
          s = "#{first}-#{last}"
        end
      else
        raise TypeError, 'Range/Integer is required'
      end

      @header['range'] = "bytes=#{s}"
      r
    end

    alias set_range range=

    def content_length
      s = @header['content-length']
      s or return nil

      m = /\d+/.match(s)
      m or raise HTTPHeaderSyntaxError, 'wrong Content-Length format'
      m[0].to_i
    end

    def chunked?
      s = @header['transfer-encoding']
      (s and /(?:\A|[^\-\w])chunked(?:[^\-\w]|\z)/i === s) ? true : false
    end

    def content_range
      s = @header['content-range']
      s or return nil

      m = %r<bytes\s+(\d+)-(\d+)/(?:\d+|\*)>i.match( s )
      m or raise HTTPHeaderSyntaxError, 'wrong Content-Range format'

      m[1].to_i .. m[2].to_i + 1
    end

    def range_length
      r = content_range
      r and r.length
    end

    def basic_auth( acc, pass )
      @header['authorization'] = 'Basic ' + ["#{acc}:#{pass}"].pack('m').strip
    end

  end


  ###
  ### request
  ###

  class HTTPGenericRequest

    include ::Net::NetPrivate::HTTPHeader

    def initialize( m, reqbody, resbody, path, uhead = nil )
      @method = m
      @request_has_body = reqbody
      @response_has_body = resbody
      @path = path
      @response = nil

      @header = tmp = {}
      return unless uhead
      uhead.each do |k,v|
        key = k.downcase
        if tmp.key? key then
          $stderr.puts "WARNING: duplicated HTTP header: #{k}" if $VERBOSE
        end
        tmp[ key ] = v.strip
      end
      tmp['accept'] ||= '*/*'
    end

    attr_reader :method
    attr_reader :path
    attr_reader :response

    def inspect
      "\#<#{type}>"
    end

    def request_body_permitted?
      @request_has_body
    end

    def response_body_permitted?
      @response_has_body
    end

    alias body_exist? response_body_permitted?


    private

    #
    # write
    #

    def exec( sock, ver, path, body, &block )
      if body then
        check_body_premitted
        check_arg_b body, block
        sendreq_with_body sock, ver, path, body, &block
      else
        check_arg_n body
        sendreq_no_body sock, ver, path
      end
      @response = r = get_response( sock )
      r
    end

    def check_body_premitted
      request_body_permitted? or
          raise ArgumentError, 'HTTP request body is not premitted'
    end

    def check_arg_b( data, block )
      if data and block then
        raise ArgumentError, 'both of data and block given'
      end
      unless data or block then
        raise ArgumentError, 'str or block required'
      end
    end

    def check_arg_n( data )
      data and raise ArgumentError, "data is not permitted for #{@method}"
    end


    def sendreq_no_body( sock, ver, path )
      request sock, ver, path
    end

    def sendreq_with_body( sock, ver, path, body )
      if block_given? then
        ac = Accumulator.new
        yield ac              # must be yield, DO NOT USE block.call
        data = ac.terminate
      else
        data = body
      end
      @header['content-length'] = data.size.to_s
      @header.delete 'transfer-encoding'

      request sock, ver, path
      sock.write data
    end

    def request( sock, ver, path )
      sock.writeline sprintf('%s %s HTTP/%s', @method, path, ver)
      canonical_each do |k,v|
        sock.writeline k + ': ' + v
      end
      sock.writeline ''
    end

    #
    # read
    #

    def get_response( sock )
      begin
        resp = ::Net::NetPrivate::HTTPResponse.new_from_socket(sock,
                                                response_body_permitted?)
      end while ContinueCode === resp
      resp
    end
  
  end


  class HTTPRequest < HTTPGenericRequest

    def initialize( path, uhead = nil )
      super type::METHOD,
            type::REQUEST_HAS_BODY,
            type::RESPONSE_HAS_BODY,
            path, uhead
    end

  end


  class Accumulator
  
    def initialize
      @buf = ''
    end

    def write( s )
      @buf.concat s
    end

    def <<( s )
      @buf.concat s
      self
    end

    def terminate
      ret = @buf
      @buf = nil
      ret
    end
  
  end

  }


  class HTTP

    class Get < ::Net::NetPrivate::HTTPRequest
      METHOD = 'GET'
      REQUEST_HAS_BODY  = false
      RESPONSE_HAS_BODY = true
    end

    class Head < ::Net::NetPrivate::HTTPRequest
      METHOD = 'HEAD'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = false
    end

    class Post < ::Net::NetPrivate::HTTPRequest
      METHOD = 'POST'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end

    class Put < ::Net::NetPrivate::HTTPRequest
      METHOD = 'PUT'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end

  end



  ###
  ### response
  ###

  net_private {

  class HTTPResponse < Response

    include ::Net::NetPrivate::HTTPHeader

    CODE_CLASS_TO_OBJ = {
      '1' => HTTPInformationCode,
      '2' => HTTPSuccessCode,
      '3' => HTTPRedirectionCode,
      '4' => HTTPClientErrorCode,
      '5' => HTTPServerErrorCode
    }

    CODE_TO_OBJ = {
      '100' => ContinueCode,
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
      '302' => HTTPMovedTemporarily,
      '303' => HTTPMovedPermanently,
      '304' => HTTPNotModified,
      '305' => HTTPUseProxy,

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
      '411' => HTTPFatalErrorCode,
      '412' => HTTPPreconditionFailed,
      '413' => HTTPRequestEntityTooLarge,
      '414' => HTTPRequestURITooLarge,
      '415' => HTTPUnsupportedMediaType,

      '500' => HTTPFatalErrorCode,
      '501' => HTTPNotImplemented,
      '502' => HTTPBadGateway,
      '503' => HTTPServiceUnavailable,
      '504' => HTTPGatewayTimeOut,
      '505' => HTTPVersionNotSupported
    }


    class << self

      def new_from_socket( sock, hasbody )
        resp = readnew( sock, hasbody )

        while true do
          line = sock.readuntil( "\n", true )   # ignore EOF
          line.sub!( /\s+\z/, '' )                 # don't use chop!
          break if line.empty?

          m = /\A([^:]+):\s*/.match( line )
          m or raise HTTPBadResponse, 'wrong header line format'
          nm = m[1]
          line = m.post_match
          if resp.key? nm then
            resp[nm] << ', ' << line
          else
            resp[nm] = line
          end
        end

        resp
      end

      private

      def readnew( sock, hasbody )
        str = sock.readline
        m = /\AHTTP(?:\/(\d+\.\d+))?\s+(\d\d\d)\s*(.*)\z/in.match( str )
        m or raise HTTPBadResponse, "wrong status line: #{str}"
        discard, httpv, stat, desc = *m.to_a
        
        new( stat, desc, sock, hasbody, httpv )
      end

    end


    def initialize( stat, msg, sock, be, hv )
      code = CODE_TO_OBJ[stat] ||
             CODE_CLASS_TO_OBJ[stat[0,1]] ||
             UnknownCode
      super code, stat, msg
      @socket = sock
      @body_exist = be
      @http_version = hv

      @header = {}
      @body = nil
      @read = false
    end

    attr_reader :http_version

    def inspect
      "#<#{type} #{code}>"
    end

    def value
      SuccessCode === self or error!
    end


    #
    # header (for backward compatibility)
    #

    def response
      self
    end

    alias header response
    alias read_header response

    #
    # body
    #

    def read_body( dest = nil, &block )
      if @read and (dest or block) then
        raise IOError, "#{type}\#read_body called twice with argument"
      end

      unless @read then
        to = procdest( dest, block )
        stream_check

        if @body_exist and code_type.body_exist? then
          read_body_0 to
          @body = to
        else
          @body = nil
        end
        @read = true
      end

      @body
    end

    alias body read_body
    alias entity read_body


    private


    def terminate
      read_body
    end

    def read_body_0( dest )
      if chunked? then
        read_chunked dest
      else
        clen = content_length
        if clen then
          @socket.read clen, dest, true   # ignore EOF
        else
          clen = range_length
          if clen then
            @socket.read clen, dest
          else
            @socket.read_all dest
          end
        end
      end
    end

    def read_chunked( dest )
      len = nil
      total = 0

      while true do
        line = @socket.readline
        m = /[0-9a-fA-F]+/.match( line )
        m or raise HTTPBadResponse, "wrong chunk size line: #{line}"
        len = m[0].hex
        break if len == 0
        @socket.read( len, dest ); total += len
        @socket.read 2   # \r\n
      end
      until @socket.readline.empty? do
        ;
      end
    end

    def stream_check
      @socket.closed? and raise IOError, 'try to read body out of block'
    end

    def procdest( dest, block )
      if dest and block then
        raise ArgumentError, 'both of arg and block are given for HTTP method'
      end
      if block then
        ::Net::NetPrivate::ReadAdapter.new block
      else
        dest || ''
      end
    end

  end

  }


  HTTPResponse         = NetPrivate::HTTPResponse
  HTTPResponseReceiver = NetPrivate::HTTPResponse

end   # module Net
