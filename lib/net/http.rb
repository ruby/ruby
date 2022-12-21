# frozen_string_literal: false
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

require 'net/protocol'
require 'uri'
require 'resolv'
autoload :OpenSSL, 'openssl'

module Net   #:nodoc:

  # :stopdoc:
  class HTTPBadResponse < StandardError; end
  class HTTPHeaderSyntaxError < StandardError; end
  # :startdoc:

  # \Class \Net::HTTP provides a rich library that implements the client
  # in a client-server model that uses the \HTTP request-response protocol.
  # For information about \HTTP, see
  #
  # - {Hypertext Transfer Protocol}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol].
  # - {Technical overview}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Technical_overview].
  #
  # Note: If you are performing only a few GET requests, consider using
  # {OpenURI}[rdoc-ref:OpenURI];
  # otherwise, read on.
  #
  # == Synopsis
  #
  # If you are already familiar with \HTTP, this synopsis may be helpful.
  #
  # {Session}[rdoc-ref:Net::HTTP@Sessions] with multiple requests for
  # {HTTP methods}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Request_methods]:
  #
  #   Net::HTTP.start(hostname) do |http|
  #     # Session started automatically before block execution.
  #     http.get(path_or_uri, headers = {})
  #     http.head(path_or_uri, headers = {})
  #     http.post(path_or_uri, data, headers = {})  # Can also have a block.
  #     http.put(path_or_uri, data, headers = {})
  #     http.delete(path_or_uri, headers = {Depth: 'Infinity'})
  #     http.options(path_or_uri, headers = {})
  #     http.trace(path_or_uri, headers = {})
  #     http.patch(path_or_uri, data, headers = {}) # Can also have a block.
  #     # Session finished automatically at block exit.
  #   end
  #
  # {Session}[rdoc-ref:Net::HTTP@Sessions] with multiple requests for
  # {WebDAV methods}[https://en.wikipedia.org/wiki/WebDAV#Implementation]:
  #
  #   Net::HTTP.start(hostname) do |http|
  #     # Session started automatically before block execution.
  #     http.copy(path_or_uri, headers = {})
  #     http.lock(path_or_uri, body, headers = {})
  #     http.mkcol(path_or_uri, body = nil, headers = {})
  #     http.move(path_or_uri, headers = {})
  #     http.propfind(path_or_uri, body = nil, headers = {'Depth' => '0'})
  #     http.proppatch(path_or_uri, body, headers = {})
  #     http.unlock(path_or_uri, body, headers = {})
  #     # Session finished automatically at block exit.
  #   end
  #
  # Each of the following methods automatically starts and finishes
  # a {session}[rdoc-ref:Net::HTTP@Sessions] that sends a single request:
  #
  #   # Return string response body.
  #   Net::HTTP.get(hostname, path, port = 80)
  #   Net::HTTP.get(uri, headers = {}, port = 80)
  #
  #   # Write string response body to $stdout.
  #   Net::HTTP.get_print(hostname, path_or_uri, port = 80)
  #   Net::HTTP.get_print(uri, headers = {}, port = 80)
  #
  #   # Return response as Net::HTTPResponse object.
  #   Net::HTTP.get_response(hostname, path_or_uri, port = 80)
  #   Net::HTTP.get_response(uri, headers = {}, port = 80)
  #
  #   Net::HTTP.post(uri, data, headers = {})
  #   Net::HTTP.post_form(uri, params)
  #
  # == About the Examples
  #
  # :include: doc/net-http/examples.rdoc
  #
  # == URIs
  #
  # On the internet, a URI
  # ({Universal Resource Identifier}[https://en.wikipedia.org/wiki/Uniform_Resource_Identifier])
  # is a string that identifies a particular resource.
  # It consists of some or all of: scheme, hostname, path, query, and fragment;
  # see {URI syntax}[https://en.wikipedia.org/wiki/Uniform_Resource_Identifier#Syntax].
  #
  # A Ruby {URI::Generic}[rdoc-ref:URI::Generic] object
  # represents an internet URI.
  # It provides, among others, methods
  # +scheme+, +hostname+, +path+, +query+, and +fragment+.
  #
  # === Schemes
  #
  # An internet \URI has
  # a {scheme}[https://en.wikipedia.org/wiki/List_of_URI_schemes].
  #
  # The two schemes supported in \Net::HTTP are <tt>'https'</tt> and <tt>'http'</tt>:
  #
  #   uri.scheme                       # => "https"
  #   URI('http://example.com').scheme # => "http"
  #
  # === Hostnames
  #
  # A hostname identifies a server (host) to which requests may be sent:
  #
  #   hostname = uri.hostname # => "jsonplaceholder.typicode.com"
  #   Net::HTTP.start(hostname) do |http|
  #     # Some HTTP stuff.
  #   end
  #
  # === Paths
  #
  # A host-specific path identifies a resource on the host:
  #
  #   _uri = uri.dup
  #   _uri.path = '/todos/1'
  #   hostname = _uri.hostname
  #   path = _uri.path
  #   Net::HTTP.get(hostname, path)
  #
  # === Queries
  #
  # A host-specific query adds name/value pairs to the URI:
  #
  #   _uri = uri.dup
  #   params = {userId: 1, completed: false}
  #   _uri.query = URI.encode_www_form(params)
  #   _uri # => #<URI::HTTPS https://jsonplaceholder.typicode.com?userId=1&completed=false>
  #   Net::HTTP.get(_uri)
  #
  # === Fragments
  #
  # A {URI fragment}[https://en.wikipedia.org/wiki/URI_fragment] has no effect
  # in \Net::HTTP;
  # the same data is returned, regardless of whether a fragment is included.
  #
  # == Request Headers
  #
  # Request headers may be used to pass additional information to the host,
  # similar to arguments passed in a method call;
  # each header is a name/value pair.
  #
  # Each of the \Net::HTTP methods that sends a request to the host
  # has optional argument +headers+,
  # where the headers are expressed as a hash of field-name/value pairs:
  #
  #   headers = {Accept: 'application/json', Connection: 'Keep-Alive'}
  #   Net::HTTP.get(uri, headers)
  #
  # See lists of both standard request fields and common request fields at
  # {Request Fields}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#Request_fields].
  # A host may also accept other custom fields.
  #
  # == Sessions
  #
  # A _session_ is a connection between a server (host) and a client that:
  #
  # - Is begun by instance method Net::HTTP#start.
  # - May contain any number of requests.
  # - Is ended by instance method Net::HTTP#finish.
  #
  # See example sessions at the {Synopsis}[rdoc-ref:Net::HTTP@Synopsis].
  #
  # === Session Using \Net::HTTP.start
  #
  # If you have many requests to make to a single host (and port),
  # consider using singleton method Net::HTTP.start with a block;
  # the method handles the session automatically by:
  #
  # - Calling #start before block execution.
  # - Executing the block.
  # - Calling #finish after block execution.
  #
  # In the block, you can use these instance methods,
  # each of which that sends a single request:
  #
  # - {HTTP methods}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Request_methods]:
  #
  #   - #get, #request_get: GET.
  #   - #head, #request_head: HEAD.
  #   - #post, #request_post: POST.
  #   - #delete: DELETE.
  #   - #options: OPTIONS.
  #   - #trace: TRACE.
  #   - #patch: PATCH.
  #
  # - {WebDAV methods}[https://en.wikipedia.org/wiki/WebDAV#Implementation]:
  #
  #   - #copy: COPY.
  #   - #lock: LOCK.
  #   - #mkcol: MKCOL.
  #   - #move: MOVE.
  #   - #propfind: PROPFIND.
  #   - #proppatch: PROPPATCH.
  #   - #unlock: UNLOCK.
  #
  # === Session Using \Net::HTTP.start and \Net::HTTP.finish
  #
  # You can manage a session manually using methods #start and #finish:
  #
  #   http = Net::HTTP.new(hostname)
  #   http.start
  #   http.get('/todos/1')
  #   http.get('/todos/2')
  #   http.delete('/posts/1')
  #   http.finish # Needed to free resources.
  #
  # === Single-Request Session
  #
  # Certain convenience methods automatically handle a session by:
  #
  # - Creating an \HTTP object
  # - Starting a session.
  # - Sending a single request.
  # - Finishing the session.
  # - Destroying the object.
  #
  # Such methods that send GET requests:
  #
  # - ::get: Returns the string response body.
  # - ::get_print: Writes the string response body to $stdout.
  # - ::get_response: Returns a Net::HTTPResponse object.
  #
  # Such methods that send POST requests:
  #
  # - ::post: Posts data to the host.
  # - ::post_form: Posts form data to the host.
  #
  # == \HTTP Requests and Responses
  #
  # Many of the methods above are convenience methods,
  # each of which sends a request and returns a string
  # without directly using \Net::HTTPRequest and \Net::HTTPResponse objects.
  #
  # You can, however, directly create a request object, send the request,
  # and retrieve the response object; see:
  #
  # - Net::HTTPRequest.
  # - Net::HTTPResponse.
  #
  # == Following Redirection
  #
  # Each Net::HTTPResponse object belongs to a class for its response code.
  #
  # For example, all 2XX responses are instances of a Net::HTTPSuccess
  # subclass, a 3XX response is an instance of a Net::HTTPRedirection
  # subclass and a 200 response is an instance of the Net::HTTPOK class.  For
  # details of response classes, see the section "HTTP Response Classes"
  # below.
  #
  # Using a case statement you can handle various types of responses properly:
  #
  #   def fetch(uri_str, limit = 10)
  #     # You should choose a better exception.
  #     raise ArgumentError, 'too many HTTP redirects' if limit == 0
  #
  #     response = Net::HTTP.get_response(URI(uri_str))
  #
  #     case response
  #     when Net::HTTPSuccess then
  #       response
  #     when Net::HTTPRedirection then
  #       location = response['location']
  #       warn "redirected to #{location}"
  #       fetch(location, limit - 1)
  #     else
  #       response.value
  #     end
  #   end
  #
  #   print fetch('http://www.ruby-lang.org')
  #
  # == Basic Authentication
  #
  # Basic authentication is performed according to
  # [RFC2617](http://www.ietf.org/rfc/rfc2617.txt).
  #
  #   uri = URI('http://example.com/index.html?key=value')
  #
  #   req = Net::HTTP::Get.new(uri)
  #   req.basic_auth 'user', 'pass'
  #
  #   res = Net::HTTP.start(uri.hostname, uri.port) {|http|
  #     http.request(req)
  #   }
  #   puts res.body
  #
  # == Streaming Response Bodies
  #
  # By default Net::HTTP reads an entire response into memory.  If you are
  # handling large files or wish to implement a progress bar you can instead
  # stream the body directly to an IO.
  #
  #   uri = URI('http://example.com/large_file')
  #
  #   Net::HTTP.start(uri.host, uri.port) do |http|
  #     request = Net::HTTP::Get.new uri
  #
  #     http.request request do |response|
  #       open 'large_file', 'w' do |io|
  #         response.read_body do |chunk|
  #           io.write chunk
  #         end
  #       end
  #     end
  #   end
  #
  # == HTTPS
  #
  # HTTPS is enabled for an HTTP connection by Net::HTTP#use_ssl=.
  #
  #   uri = URI('https://secure.example.com/some_path?query=string')
  #
  #   Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
  #     request = Net::HTTP::Get.new uri
  #     response = http.request request # Net::HTTPResponse object
  #   end
  #
  # Or if you simply want to make a GET request, you may pass in an URI
  # object that has an HTTPS URL. Net::HTTP automatically turns on TLS
  # verification if the URI object has a 'https' URI scheme.
  #
  #   uri = URI('https://example.com/')
  #   Net::HTTP.get(uri) # => String
  #
  # In previous versions of Ruby you would need to require 'net/https' to use
  # HTTPS. This is no longer true.
  #
  # == Proxies
  #
  # Net::HTTP will automatically create a proxy from the +http_proxy+
  # environment variable if it is present.  To disable use of +http_proxy+,
  # pass +nil+ for the proxy address.
  #
  # You may also create a custom proxy:
  #
  #   proxy_addr = 'your.proxy.host'
  #   proxy_port = 8080
  #
  #   Net::HTTP.new('example.com', nil, proxy_addr, proxy_port).start { |http|
  #     # always proxy via your.proxy.addr:8080
  #   }
  #
  # See Net::HTTP.new for further details and examples such as proxies that
  # require a username and password.
  #
  # == Compression
  #
  # Net::HTTP automatically adds Accept-Encoding for compression of response
  # bodies and automatically decompresses gzip and deflate responses unless a
  # Range header was sent.
  #
  # Compression can be disabled through the Accept-Encoding: identity header.
  #
  class HTTP < Protocol

    # :stopdoc:
    VERSION = "0.3.2"
    Revision = %q$Revision$.split[1]
    HTTPVersion = '1.1'
    begin
      require 'zlib'
      HAVE_ZLIB=true
    rescue LoadError
      HAVE_ZLIB=false
    end
    # :startdoc:

    # Returns +true+; retained for compatibility.
    def HTTP.version_1_2
      true
    end

    # Returns +true+; retained for compatibility.
    def HTTP.version_1_2?
      true
    end

    # Returns +false+; retained for compatibility.
    def HTTP.version_1_1?  #:nodoc:
      false
    end

    class << HTTP
      alias is_version_1_1? version_1_1?   #:nodoc:
      alias is_version_1_2? version_1_2?   #:nodoc:
    end

    # :call-seq:
    #   Net::HTTP.get_print(hostname, path, port = 80) -> nil
    #   Net::HTTP:get_print(uri, headers = {}, port = uri.port) -> nil
    #
    # Like Net::HTTP.get, but writes the returned body to $stdout;
    # returns +nil+.
    def HTTP.get_print(uri_or_host, path_or_headers = nil, port = nil)
      get_response(uri_or_host, path_or_headers, port) {|res|
        res.read_body do |chunk|
          $stdout.print chunk
        end
      }
      nil
    end

    # :call-seq:
    #   Net::HTTP.get(hostname, path, port = 80) -> body
    #   Net::HTTP:get(uri, headers = {}, port = uri.port) -> body
    #
    # Sends a GET request and returns the \HTTP response body as a string.
    #
    # With string arguments +hostname+ and +path+:
    #
    #   hostname = 'jsonplaceholder.typicode.com'
    #   path = '/todos/1'
    #   puts Net::HTTP.get(hostname, path)
    #
    # Output:
    #
    #   {
    #     "userId": 1,
    #     "id": 1,
    #     "title": "delectus aut autem",
    #     "completed": false
    #   }
    #
    # With URI object +uri+ and optional hash argument +headers+:
    #
    #   uri = URI('https://jsonplaceholder.typicode.com/todos/1')
    #   headers = {'Content-type' => 'application/json; charset=UTF-8'}
    #   Net::HTTP.get(uri, headers)
    #
    # Related:
    #
    # - Net::HTTP::Get: request class for \HTTP method +GET+.
    # - Net::HTTP#get: convenience method for \HTTP method +GET+.
    #
    def HTTP.get(uri_or_host, path_or_headers = nil, port = nil)
      get_response(uri_or_host, path_or_headers, port).body
    end

    # :call-seq:
    #   Net::HTTP.get_response(hostname, path, port = 80) -> http_response
    #   Net::HTTP:get_response(uri, headers = {}, port = uri.port) -> http_response
    #
    # Like Net::HTTP.get, but returns a Net::HTTPResponse object
    # instead of the body string.
    def HTTP.get_response(uri_or_host, path_or_headers = nil, port = nil, &block)
      if path_or_headers && !path_or_headers.is_a?(Hash)
        host = uri_or_host
        path = path_or_headers
        new(host, port || HTTP.default_port).start {|http|
          return http.request_get(path, &block)
        }
      else
        uri = uri_or_host
        headers = path_or_headers
        start(uri.hostname, uri.port,
              :use_ssl => uri.scheme == 'https') {|http|
          return http.request_get(uri, headers, &block)
        }
      end
    end

    # Posts data to a host; returns a Net::HTTPResponse object.
    #
    # Argument +url+ must be a URL;
    # argument +data+ must be a string:
    #
    #   _uri = uri.dup
    #   _uri.path = '/posts'
    #   data = '{"title": "foo", "body": "bar", "userId": 1}'
    #   headers = {'content-type': 'application/json'}
    #   res = Net::HTTP.post(_uri, data, headers) # => #<Net::HTTPCreated 201 Created readbody=true>
    #   puts res.body
    #
    # Output:
    #
    #   {
    #     "title": "foo",
    #     "body": "bar",
    #     "userId": 1,
    #     "id": 101
    #   }
    #
    # Related:
    #
    # - Net::HTTP::Post: request class for \HTTP method +POST+.
    # - Net::HTTP#post: convenience method for \HTTP method +POST+.
    #
    def HTTP.post(url, data, header = nil)
      start(url.hostname, url.port,
            :use_ssl => url.scheme == 'https' ) {|http|
        http.post(url, data, header)
      }
    end

    # Posts data to a host; returns a Net::HTTPResponse object.
    #
    # Argument +url+ must be a URI;
    # argument +data+ must be a hash:
    #
    #   _uri = uri.dup
    #   _uri.path = '/posts'
    #   data = {title: 'foo', body: 'bar', userId: 1}
    #   res = Net::HTTP.post_form(_uri, data) # => #<Net::HTTPCreated 201 Created readbody=true>
    #   puts res.body
    #
    # Output:
    #
    #   {
    #     "title": "foo",
    #     "body": "bar",
    #     "userId": "1",
    #     "id": 101
    #   }
    #
    def HTTP.post_form(url, params)
      req = Post.new(url)
      req.form_data = params
      req.basic_auth url.user, url.password if url.user
      start(url.hostname, url.port,
            :use_ssl => url.scheme == 'https' ) {|http|
        http.request(req)
      }
    end

    #
    # HTTP session management
    #

    # Returns intger +80+, the default port to use for HTTP requests:
    #
    #   Net::HTTP.default_port # => 80
    #
    def HTTP.default_port
      http_default_port()
    end

    # Returns integer +80+, the default port to use for HTTP requests:
    #
    #   Net::HTTP.http_default_port # => 80
    #
    def HTTP.http_default_port
      80
    end

    # Returns integer +443+, the default port to use for HTTPS requests:
    #
    #   Net::HTTP.https_default_port # => 443
    #
    def HTTP.https_default_port
      443
    end

    def HTTP.socket_type   #:nodoc: obsolete
      BufferedIO
    end

    # :call-seq:
    #   HTTP.start(address, port = nil, p_addr = :ENV, p_port = nil, p_user = nil, p_pass = nil, opts) -> http
    #   HTTP.start(address, port = nil, p_addr = :ENV, p_port = nil, p_user = nil, p_pass = nil, opts) {|http| ... } -> object
    #
    # Creates a new \Net::HTTP object, +http+, via \Net::HTTP.new:
    #
    #   Net::HTTP.new(address, port, p_addr, p_port, p_user, p_pass)
    #
    # - For arguments +hostname+ through +p_pass+, see Net::HTTP.new.
    # - For argument +opts+, see below.
    #
    # Note: If +port+ is +nil+ and <tt>opts[:use_ssl]</tt> is a truthy value,
    # the value passed to +new+ is Net::HTTP.https_default_port, not +port+.
    #
    # With no block given:
    #
    # - Calls <tt>http.start</tt> with no block (see #start),
    #   which opens a TCP connection and \HTTP session.
    # - Returns +http+.
    # - The caller should call #finish to close the session:
    #
    #     http = Net::HTTP.start(hostname)
    #     http.started? # => true
    #     http.finish
    #     http.started? # => false
    #
    # With a block given:
    #
    # - Calls <tt>http.start</tt> with the block (see #start), which:
    #
    #   - Opens a TCP connection and \HTTP session.
    #   - Calls the block,
    #     which may make any number of requests to the host.
    #   - Closes the \HTTP session and TCP connection on block exit.
    #   - Returns the block's value +object+.
    #
    # - Returns +object+.
    #
    # Example:
    #
    #   hostname = 'jsonplaceholder.typicode.com'
    #   Net::HTTP.start(hostname) do |http|
    #     puts http.get('/todos/1').body
    #     puts http.get('/todos/2').body
    #   end
    #
    # Output:
    #
    #   {
    #     "userId": 1,
    #     "id": 1,
    #     "title": "delectus aut autem",
    #     "completed": false
    #   }
    #   {
    #     "userId": 1,
    #     "id": 2,
    #     "title": "quis ut nam facilis et officia qui",
    #     "completed": false
    #   }
    #
    # If the last argument given is a hash, it is the +opts+ hash,
    # where each key is a method or accessor to be called,
    # and its value is the value to be set.
    #
    # The keys may include:
    #
    # - #ca_file
    # - #ca_path
    # - #cert
    # - #cert_store
    # - #ciphers
    # - #close_on_empty_response
    # - +ipaddr+ (calls #ipaddr=)
    # - #keep_alive_timeout
    # - #key
    # - #open_timeout
    # - #read_timeout
    # - #ssl_timeout
    # - #ssl_version
    # - +use_ssl+ (calls #use_ssl=)
    # - #verify_callback
    # - #verify_depth
    # - #verify_mode
    # - #write_timeout
    #
    def HTTP.start(address, *arg, &block) # :yield: +http+
      arg.pop if opt = Hash.try_convert(arg[-1])
      port, p_addr, p_port, p_user, p_pass = *arg
      p_addr = :ENV if arg.size < 2
      port = https_default_port if !port && opt && opt[:use_ssl]
      http = new(address, port, p_addr, p_port, p_user, p_pass)
      http.ipaddr = opt[:ipaddr] if opt && opt[:ipaddr]

      if opt
        if opt[:use_ssl]
          opt = {verify_mode: OpenSSL::SSL::VERIFY_PEER}.update(opt)
        end
        http.methods.grep(/\A(\w+)=\z/) do |meth|
          key = $1.to_sym
          opt.key?(key) or next
          http.__send__(meth, opt[key])
        end
      end

      http.start(&block)
    end

    class << HTTP
      alias newobj new # :nodoc:
    end

    # Returns a new Net::HTTP object +http+
    # (but does not open a TCP connection or HTTP session).
    #
    # <b>No Proxy</b>
    #
    # With only string argument +hostname+ given
    # (and <tt>ENV['http_proxy']</tt> undefined or +nil+),
    # the returned +http+:
    #
    # - Has the given address.
    # - Has the default port number, Net::HTTP.default_port (80).
    # - Has no proxy.
    #
    # Example:
    #
    #   http = Net::HTTP.new(hostname)
    #   # => #<Net::HTTP jsonplaceholder.typicode.com:80 open=false>
    #   http.address # => "jsonplaceholder.typicode.com"
    #   http.port    # => 80
    #   http.proxy?  # => false
    #
    # With integer argument +port+ also given,
    # the returned +http+ has the given port:
    #
    #   http = Net::HTTP.new(hostname, 8000)
    #   # => #<Net::HTTP jsonplaceholder.typicode.com:8000 open=false>
    #   http.port # => 8000
    #
    # <b>Proxy Using Argument +p_addr+ as a \String</b>
    #
    # When argument +p_addr+ is a string hostname,
    # the returned +http+ has a proxy:
    #
    #   http = Net::HTTP.new(hostname, nil, 'proxy.example')
    #   # => #<Net::HTTP jsonplaceholder.typicode.com:80 open=false>
    #   http.proxy?        # => true
    #   http.proxy_address # => "proxy.example"
    #   # These use default values.
    #   http.proxy_port    # => 80
    #   http.proxy_user    # => nil
    #   http.proxy_pass    # => nil
    #
    # The port, username, and password for the proxy may also be given:
    #
    #   http = Net::HTTP.new(hostname, nil, 'proxy.example', 8000, 'pname', 'ppass')
    #   # => #<Net::HTTP jsonplaceholder.typicode.com:80 open=false>
    #   http.proxy?        # => true
    #   http.proxy_address # => "proxy.example"
    #   http.proxy_port    # => 8000
    #   http.proxy_user    # => "pname"
    #   http.proxy_pass    # => "ppass"
    #
    # <b>Proxy Using <tt>ENV['http_proxy']</tt></b>
    #
    # When environment variable <tt>'http_proxy'</tt>
    # is set to a \URI string,
    # the returned +http+ will have that URI as its proxy;
    # note that the \URI string must have a protocol
    # such as <tt>'http'</tt> or <tt>'https'</tt>:
    #
    #   ENV['http_proxy'] = 'http://example.com'
    #   # => "http://example.com"
    #   http = Net::HTTP.new(hostname)
    #   # => #<Net::HTTP jsonplaceholder.typicode.com:80 open=false>
    #   http.proxy?        # => true
    #   http.address       # => "jsonplaceholder.typicode.com"
    #   http.proxy_address # => "example.com"
    #
    # The \URI string may include proxy username, password, and port number:
    #
    #   ENV['http_proxy'] = 'http://pname:ppass@example.com:8000'
    #   # => "http://pname:ppass@example.com:8000"
    #   http = Net::HTTP.new(hostname)
    #   # => #<Net::HTTP jsonplaceholder.typicode.com:80 open=false>
    #   http.proxy_port # => 8000
    #   http.proxy_user # => "pname"
    #   http.proxy_pass # => "ppass"
    #
    # <b>Argument +p_no_proxy+</b>
    #
    # You can use argument +p_no_proxy+ to reject certain proxies:
    #
    # - Reject a certain address:
    #
    #     http = Net::HTTP.new('example.com', nil, 'proxy.example', 8000, 'pname', 'ppass', 'proxy.example')
    #     http.proxy_address # => nil
    #
    # - Reject certain domains or subdomains:
    #
    #     http = Net::HTTP.new('example.com', nil, 'my.proxy.example', 8000, 'pname', 'ppass', 'proxy.example')
    #     http.proxy_address # => nil
    #
    # - Reject certain addresses and port combinations:
    #
    #     http = Net::HTTP.new('example.com', nil, 'proxy.example', 8000, 'pname', 'ppass', 'proxy.example:1234')
    #     http.proxy_address # => "proxy.example"
    #
    #     http = Net::HTTP.new('example.com', nil, 'proxy.example', 8000, 'pname', 'ppass', 'proxy.example:8000')
    #     http.proxy_address # => nil
    #
    # - Reject a list of the types above delimited using a comma:
    #
    #     http = Net::HTTP.new('example.com', nil, 'proxy.example', 8000, 'pname', 'ppass', 'my.proxy,proxy.example:8000')
    #     http.proxy_address # => nil
    #
    #     http = Net::HTTP.new('example.com', nil, 'my.proxy', 8000, 'pname', 'ppass', 'my.proxy,proxy.example:8000')
    #     http.proxy_address # => nil
    #
    def HTTP.new(address, port = nil, p_addr = :ENV, p_port = nil, p_user = nil, p_pass = nil, p_no_proxy = nil)
      http = super address, port

      if proxy_class? then # from Net::HTTP::Proxy()
        http.proxy_from_env = @proxy_from_env
        http.proxy_address  = @proxy_address
        http.proxy_port     = @proxy_port
        http.proxy_user     = @proxy_user
        http.proxy_pass     = @proxy_pass
      elsif p_addr == :ENV then
        http.proxy_from_env = true
      else
        if p_addr && p_no_proxy && !URI::Generic.use_proxy?(p_addr, p_addr, p_port, p_no_proxy)
          p_addr = nil
          p_port = nil
        end
        http.proxy_address = p_addr
        http.proxy_port    = p_port || default_port
        http.proxy_user    = p_user
        http.proxy_pass    = p_pass
      end

      http
    end

    # Creates a new Net::HTTP object for the specified server address,
    # without opening the TCP connection or initializing the HTTP session.
    # The +address+ should be a DNS hostname or IP address.
    def initialize(address, port = nil)
      @address = address
      @port    = (port || HTTP.default_port)
      @ipaddr = nil
      @local_host = nil
      @local_port = nil
      @curr_http_version = HTTPVersion
      @keep_alive_timeout = 2
      @last_communicated = nil
      @close_on_empty_response = false
      @socket  = nil
      @started = false
      @open_timeout = 60
      @read_timeout = 60
      @write_timeout = 60
      @continue_timeout = nil
      @max_retries = 1
      @debug_output = nil
      @response_body_encoding = false
      @ignore_eof = true

      @proxy_from_env = false
      @proxy_uri      = nil
      @proxy_address  = nil
      @proxy_port     = nil
      @proxy_user     = nil
      @proxy_pass     = nil

      @use_ssl = false
      @ssl_context = nil
      @ssl_session = nil
      @sspi_enabled = false
      SSL_IVNAMES.each do |ivname|
        instance_variable_set ivname, nil
      end
    end

    # Returns a string representation of +self+:
    #
    #   Net::HTTP.new(hostname).inspect
    #   # => "#<Net::HTTP jsonplaceholder.typicode.com:80 open=false>"
    #
    def inspect
      "#<#{self.class} #{@address}:#{@port} open=#{started?}>"
    end

    # *WARNING* This method opens a serious security hole.
    # Never use this method in production code.
    #
    # Sets the output stream for debugging:
    #
    #   http = Net::HTTP.new(hostname)
    #   File.open('t.tmp', 'w') do |file|
    #     http.set_debug_output(file)
    #     http.start
    #     http.get('/nosuch/1')
    #     http.finish
    #   end
    #   puts File.read('t.tmp')
    #
    # Output:
    #
    #   opening connection to jsonplaceholder.typicode.com:80...
    #   opened
    #   <- "GET /nosuch/1 HTTP/1.1\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nHost: jsonplaceholder.typicode.com\r\n\r\n"
    #   -> "HTTP/1.1 404 Not Found\r\n"
    #   -> "Date: Mon, 12 Dec 2022 21:14:11 GMT\r\n"
    #   -> "Content-Type: application/json; charset=utf-8\r\n"
    #   -> "Content-Length: 2\r\n"
    #   -> "Connection: keep-alive\r\n"
    #   -> "X-Powered-By: Express\r\n"
    #   -> "X-Ratelimit-Limit: 1000\r\n"
    #   -> "X-Ratelimit-Remaining: 999\r\n"
    #   -> "X-Ratelimit-Reset: 1670879660\r\n"
    #   -> "Vary: Origin, Accept-Encoding\r\n"
    #   -> "Access-Control-Allow-Credentials: true\r\n"
    #   -> "Cache-Control: max-age=43200\r\n"
    #   -> "Pragma: no-cache\r\n"
    #   -> "Expires: -1\r\n"
    #   -> "X-Content-Type-Options: nosniff\r\n"
    #   -> "Etag: W/\"2-vyGp6PvFo4RvsFtPoIWeCReyIC8\"\r\n"
    #   -> "Via: 1.1 vegur\r\n"
    #   -> "CF-Cache-Status: MISS\r\n"
    #   -> "Server-Timing: cf-q-config;dur=1.3000000762986e-05\r\n"
    #   -> "Report-To: {\"endpoints\":[{\"url\":\"https:\\/\\/a.nel.cloudflare.com\\/report\\/v3?s=yOr40jo%2BwS1KHzhTlVpl54beJ5Wx2FcG4gGV0XVrh3X9OlR5q4drUn2dkt5DGO4GDcE%2BVXT7CNgJvGs%2BZleIyMu8CLieFiDIvOviOY3EhHg94m0ZNZgrEdpKD0S85S507l1vsEwEHkoTm%2Ff19SiO\"}],\"group\":\"cf-nel\",\"max_age\":604800}\r\n"
    #   -> "NEL: {\"success_fraction\":0,\"report_to\":\"cf-nel\",\"max_age\":604800}\r\n"
    #   -> "Server: cloudflare\r\n"
    #   -> "CF-RAY: 778977dc484ce591-DFW\r\n"
    #   -> "alt-svc: h3=\":443\"; ma=86400, h3-29=\":443\"; ma=86400\r\n"
    #   -> "\r\n"
    #   reading 2 bytes...
    #   -> "{}"
    #   read 2 bytes
    #   Conn keep-alive
    #
    def set_debug_output(output)
      warn 'Net::HTTP#set_debug_output called after HTTP started', uplevel: 1 if started?
      @debug_output = output
    end

    # The DNS host name or IP address to connect to.
    attr_reader :address

    # The port number to connect to.
    attr_reader :port

    # The local host used to establish the connection.
    attr_accessor :local_host

    # The local port used to establish the connection.
    attr_accessor :local_port

    # The encoding to use for the response body.  If Encoding, uses the
    # specified encoding.  If other true value, tries to detect the response
    # body encoding.
    attr_reader :response_body_encoding

    # Sets the encoding to be used for the response body;
    # returns the encoding.
    #
    # The given +value+ may be:
    #
    # - An Encoding object.
    # - The name of an encoding.
    # - An alias for an encoding name.
    #
    # See {Encoding}[rdoc-ref:Encoding].
    #
    # Examples:
    #
    #   http = Net::HTTP.new(hostname)
    #   http.response_body_encoding = Encoding::US_ASCII # => #<Encoding:US-ASCII>
    #   http.response_body_encoding = 'US-ASCII'         # => "US-ASCII"
    #   http.response_body_encoding = 'ASCII'            # => "ASCII"
    #
    def response_body_encoding=(value)
      value = Encoding.find(value) if value.is_a?(String)
      @response_body_encoding = value
    end

    attr_writer :proxy_from_env
    attr_writer :proxy_address
    attr_writer :proxy_port
    attr_writer :proxy_user
    attr_writer :proxy_pass

    # Returns the IP address for the connection.
    #
    # If the session has not been started,
    # returns the value set by #ipaddr=,
    # or +nil+ if it has not been set:
    #
    #   http = Net::HTTP.new(hostname)
    #   http.ipaddr # => nil
    #   http.ipaddr = '172.67.155.76'
    #   http.ipaddr # => "172.67.155.76"
    #
    # If the session has been started,
    # returns the IP address from the socket:
    #
    #   http = Net::HTTP.new(hostname)
    #   http.start
    #   http.ipaddr # => "172.67.155.76"
    #   http.finish
    #
    def ipaddr
      started? ?  @socket.io.peeraddr[3] : @ipaddr
    end

    # Sets the IP address for the connection:
    #
    #   http = Net::HTTP.new(hostname)
    #   http.ipaddr # => nil
    #   http.ipaddr = '172.67.155.76'
    #   http.ipaddr # => "172.67.155.76"
    #
    # The IP address may not be set if the session has been started.
    def ipaddr=(addr)
      raise IOError, "ipaddr value changed, but session already started" if started?
      @ipaddr = addr
    end

    # Number of seconds to wait for the connection to open. Any number
    # may be used, including Floats for fractional seconds. If the HTTP
    # object cannot open a connection in this many seconds, it raises a
    # Net::OpenTimeout exception. The default value is 60 seconds.
    attr_accessor :open_timeout

    # Number of seconds to wait for one block to be read (via one read(2)
    # call). Any number may be used, including Floats for fractional
    # seconds. If the HTTP object cannot read data in this many seconds,
    # it raises a Net::ReadTimeout exception. The default value is 60 seconds.
    attr_reader :read_timeout

    # Number of seconds to wait for one block to be written (via one write(2)
    # call). Any number may be used, including Floats for fractional
    # seconds. If the HTTP object cannot write data in this many seconds,
    # it raises a Net::WriteTimeout exception. The default value is 60 seconds.
    # Net::WriteTimeout is not raised on Windows.
    attr_reader :write_timeout

    # Sets the maximum number of times to retry an idempotent request in case of
    # Net::ReadTimeout, IOError, EOFError, Errno::ECONNRESET,
    # Errno::ECONNABORTED, Errno::EPIPE, OpenSSL::SSL::SSLError,
    # Timeout::Error.
    # The initial value is 1.
    #
    # Argument +retries+ must be a non-negative numeric value:
    #
    #   http = Net::HTTP.new(hostname)
    #   http.max_retries = 2   # => 2
    #   http.max_retries       # => 2
    #
    def max_retries=(retries)
      retries = retries.to_int
      if retries < 0
        raise ArgumentError, 'max_retries should be non-negative integer number'
      end
      @max_retries = retries
    end

    attr_reader :max_retries

    # Sets the read timeout, in seconds, for +self+ to integer +sec+;
    # the initial value is 60.
    #
    # Argument +sec+ must be a non-negative numeric value:
    #
    #   http = Net::HTTP.new(hostname)
    #   http.read_timeout # => 60
    #   http.get('/todos/1') # => #<Net::HTTPOK 200 OK readbody=true>
    #   http.read_timeout = 0
    #   http.get('/todos/1') # Raises Net::ReadTimeout.
    #
    def read_timeout=(sec)
      @socket.read_timeout = sec if @socket
      @read_timeout = sec
    end

    # Sets the write timeout, in seconds, for +self+ to integer +sec+;
    # the initial value is 60.
    #
    # Argument +sec+ must be a non-negative numeric value.
    #
    def write_timeout=(sec)
      @socket.write_timeout = sec if @socket
      @write_timeout = sec
    end

    # Seconds to wait for 100 Continue response. If the HTTP object does not
    # receive a response in this many seconds it sends the request body. The
    # default value is +nil+.
    attr_reader :continue_timeout

    # Setter for the continue_timeout attribute.
    def continue_timeout=(sec)
      @socket.continue_timeout = sec if @socket
      @continue_timeout = sec
    end

    # Seconds to reuse the connection of the previous request.
    # If the idle time is less than this Keep-Alive Timeout,
    # Net::HTTP reuses the TCP/IP socket used by the previous communication.
    # The default value is 2 seconds.
    attr_accessor :keep_alive_timeout

    # Whether to ignore EOF when reading response bodies with defined
    # Content-Length headers. For backwards compatibility, the default is true.
    attr_accessor :ignore_eof

    # Returns true if the HTTP session has been started.
    def started?
      @started
    end

    alias active? started?   #:nodoc: obsolete

    attr_accessor :close_on_empty_response

    # Returns true if SSL/TLS is being used with HTTP.
    def use_ssl?
      @use_ssl
    end

    # Turn on/off SSL.
    # This flag must be set before starting session.
    # If you change use_ssl value after session started,
    # a Net::HTTP object raises IOError.
    def use_ssl=(flag)
      flag = flag ? true : false
      if started? and @use_ssl != flag
        raise IOError, "use_ssl value changed, but session already started"
      end
      @use_ssl = flag
    end

    SSL_IVNAMES = [
      :@ca_file,
      :@ca_path,
      :@cert,
      :@cert_store,
      :@ciphers,
      :@extra_chain_cert,
      :@key,
      :@ssl_timeout,
      :@ssl_version,
      :@min_version,
      :@max_version,
      :@verify_callback,
      :@verify_depth,
      :@verify_mode,
      :@verify_hostname,
    ]
    SSL_ATTRIBUTES = [
      :ca_file,
      :ca_path,
      :cert,
      :cert_store,
      :ciphers,
      :extra_chain_cert,
      :key,
      :ssl_timeout,
      :ssl_version,
      :min_version,
      :max_version,
      :verify_callback,
      :verify_depth,
      :verify_mode,
      :verify_hostname,
    ]

    # Sets path of a CA certification file in PEM format.
    #
    # The file can contain several CA certificates.
    attr_accessor :ca_file

    # Sets path of a CA certification directory containing certifications in
    # PEM format.
    attr_accessor :ca_path

    # Sets an OpenSSL::X509::Certificate object as client certificate.
    # (This method is appeared in Michal Rokos's OpenSSL extension).
    attr_accessor :cert

    # Sets the X509::Store to verify peer certificate.
    attr_accessor :cert_store

    # Sets the available ciphers.  See OpenSSL::SSL::SSLContext#ciphers=
    attr_accessor :ciphers

    # Sets the extra X509 certificates to be added to the certificate chain.
    # See OpenSSL::SSL::SSLContext#extra_chain_cert=
    attr_accessor :extra_chain_cert

    # Sets an OpenSSL::PKey::RSA or OpenSSL::PKey::DSA object.
    # (This method is appeared in Michal Rokos's OpenSSL extension.)
    attr_accessor :key

    # Sets the SSL timeout seconds.
    attr_accessor :ssl_timeout

    # Sets the SSL version.  See OpenSSL::SSL::SSLContext#ssl_version=
    attr_accessor :ssl_version

    # Sets the minimum SSL version.  See OpenSSL::SSL::SSLContext#min_version=
    attr_accessor :min_version

    # Sets the maximum SSL version.  See OpenSSL::SSL::SSLContext#max_version=
    attr_accessor :max_version

    # Sets the verify callback for the server certification verification.
    attr_accessor :verify_callback

    # Sets the maximum depth for the certificate chain verification.
    attr_accessor :verify_depth

    # Sets the flags for server the certification verification at beginning of
    # SSL/TLS session.
    #
    # OpenSSL::SSL::VERIFY_NONE or OpenSSL::SSL::VERIFY_PEER are acceptable.
    attr_accessor :verify_mode

    # Sets to check the server certificate is valid for the hostname.
    # See OpenSSL::SSL::SSLContext#verify_hostname=
    attr_accessor :verify_hostname

    # Returns the X.509 certificates the server presented.
    def peer_cert
      if not use_ssl? or not @socket
        return nil
      end
      @socket.io.peer_cert
    end

    # Opens a TCP connection and HTTP session.
    #
    # When this method is called with a block, it passes the Net::HTTP
    # object to the block, and closes the TCP connection and HTTP session
    # after the block has been executed.
    #
    # When called with a block, it returns the return value of the
    # block; otherwise, it returns self.
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
      if use_ssl?
        # reference early to load OpenSSL before connecting,
        # as OpenSSL may take time to load.
        @ssl_context = OpenSSL::SSL::SSLContext.new
      end

      if proxy? then
        conn_addr = proxy_address
        conn_port = proxy_port
      else
        conn_addr = conn_address
        conn_port = port
      end

      debug "opening connection to #{conn_addr}:#{conn_port}..."
      s = Timeout.timeout(@open_timeout, Net::OpenTimeout) {
        begin
          TCPSocket.open(conn_addr, conn_port, @local_host, @local_port)
        rescue => e
          raise e, "Failed to open TCP connection to " +
            "#{conn_addr}:#{conn_port} (#{e.message})"
        end
      }
      s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      debug "opened"
      if use_ssl?
        if proxy?
          plain_sock = BufferedIO.new(s, read_timeout: @read_timeout,
                                      write_timeout: @write_timeout,
                                      continue_timeout: @continue_timeout,
                                      debug_output: @debug_output)
          buf = "CONNECT #{conn_address}:#{@port} HTTP/#{HTTPVersion}\r\n"
          buf << "Host: #{@address}:#{@port}\r\n"
          if proxy_user
            credential = ["#{proxy_user}:#{proxy_pass}"].pack('m0')
            buf << "Proxy-Authorization: Basic #{credential}\r\n"
          end
          buf << "\r\n"
          plain_sock.write(buf)
          HTTPResponse.read_new(plain_sock).value
          # assuming nothing left in buffers after successful CONNECT response
        end

        ssl_parameters = Hash.new
        iv_list = instance_variables
        SSL_IVNAMES.each_with_index do |ivname, i|
          if iv_list.include?(ivname)
            value = instance_variable_get(ivname)
            unless value.nil?
              ssl_parameters[SSL_ATTRIBUTES[i]] = value
            end
          end
        end
        @ssl_context.set_params(ssl_parameters)
        unless @ssl_context.session_cache_mode.nil? # a dummy method on JRuby
          @ssl_context.session_cache_mode =
              OpenSSL::SSL::SSLContext::SESSION_CACHE_CLIENT |
                  OpenSSL::SSL::SSLContext::SESSION_CACHE_NO_INTERNAL_STORE
        end
        if @ssl_context.respond_to?(:session_new_cb) # not implemented under JRuby
          @ssl_context.session_new_cb = proc {|sock, sess| @ssl_session = sess }
        end

        # Still do the post_connection_check below even if connecting
        # to IP address
        verify_hostname = @ssl_context.verify_hostname

        # Server Name Indication (SNI) RFC 3546/6066
        case @address
        when Resolv::IPv4::Regex, Resolv::IPv6::Regex
          # don't set SNI, as IP addresses in SNI is not valid
          # per RFC 6066, section 3.

          # Avoid openssl warning
          @ssl_context.verify_hostname = false
        else
          ssl_host_address = @address
        end

        debug "starting SSL for #{conn_addr}:#{conn_port}..."
        s = OpenSSL::SSL::SSLSocket.new(s, @ssl_context)
        s.sync_close = true
        s.hostname = ssl_host_address if s.respond_to?(:hostname=) && ssl_host_address

        if @ssl_session and
           Process.clock_gettime(Process::CLOCK_REALTIME) < @ssl_session.time.to_f + @ssl_session.timeout
          s.session = @ssl_session
        end
        ssl_socket_connect(s, @open_timeout)
        if (@ssl_context.verify_mode != OpenSSL::SSL::VERIFY_NONE) && verify_hostname
          s.post_connection_check(@address)
        end
        debug "SSL established, protocol: #{s.ssl_version}, cipher: #{s.cipher[0]}"
      end
      @socket = BufferedIO.new(s, read_timeout: @read_timeout,
                               write_timeout: @write_timeout,
                               continue_timeout: @continue_timeout,
                               debug_output: @debug_output)
      @last_communicated = nil
      on_connect
    rescue => exception
      if s
        debug "Conn close because of connect error #{exception}"
        s.close
      end
      raise
    end
    private :connect

    def on_connect
    end
    private :on_connect

    # Finishes the HTTP session and closes the TCP connection.
    # Raises IOError if the session has not been started.
    def finish
      raise IOError, 'HTTP session not yet started' unless started?
      do_finish
    end

    def do_finish
      @started = false
      @socket.close if @socket
      @socket = nil
    end
    private :do_finish

    #
    # proxy
    #

    public

    # no proxy
    @is_proxy_class = false
    @proxy_from_env = false
    @proxy_addr = nil
    @proxy_port = nil
    @proxy_user = nil
    @proxy_pass = nil

    # Creates an HTTP proxy class which behaves like Net::HTTP, but
    # performs all access via the specified proxy.
    #
    # This class is obsolete.  You may pass these same parameters directly to
    # Net::HTTP.new.  See Net::HTTP.new for details of the arguments.
    def HTTP.Proxy(p_addr = :ENV, p_port = nil, p_user = nil, p_pass = nil) #:nodoc:
      return self unless p_addr

      Class.new(self) {
        @is_proxy_class = true

        if p_addr == :ENV then
          @proxy_from_env = true
          @proxy_address = nil
          @proxy_port    = nil
        else
          @proxy_from_env = false
          @proxy_address = p_addr
          @proxy_port    = p_port || default_port
        end

        @proxy_user = p_user
        @proxy_pass = p_pass
      }
    end

    class << HTTP
      # returns true if self is a class which was created by HTTP::Proxy.
      def proxy_class?
        defined?(@is_proxy_class) ? @is_proxy_class : false
      end

      # Address of proxy host. If Net::HTTP does not use a proxy, nil.
      attr_reader :proxy_address

      # Port number of proxy host. If Net::HTTP does not use a proxy, nil.
      attr_reader :proxy_port

      # User name for accessing proxy. If Net::HTTP does not use a proxy, nil.
      attr_reader :proxy_user

      # User password for accessing proxy. If Net::HTTP does not use a proxy,
      # nil.
      attr_reader :proxy_pass
    end

    # True if requests for this connection will be proxied
    def proxy?
      !!(@proxy_from_env ? proxy_uri : @proxy_address)
    end

    # True if the proxy for this connection is determined from the environment
    def proxy_from_env?
      @proxy_from_env
    end

    # The proxy URI determined from the environment for this connection.
    def proxy_uri # :nodoc:
      return if @proxy_uri == false
      @proxy_uri ||= URI::HTTP.new(
        "http".freeze, nil, address, port, nil, nil, nil, nil, nil
      ).find_proxy || false
      @proxy_uri || nil
    end

    # The address of the proxy server, if one is configured.
    def proxy_address
      if @proxy_from_env then
        proxy_uri&.hostname
      else
        @proxy_address
      end
    end

    # The port of the proxy server, if one is configured.
    def proxy_port
      if @proxy_from_env then
        proxy_uri&.port
      else
        @proxy_port
      end
    end

    # The username of the proxy server, if one is configured.
    def proxy_user
      if @proxy_from_env
        user = proxy_uri&.user
        unescape(user) if user
      else
        @proxy_user
      end
    end

    # The password of the proxy server, if one is configured.
    def proxy_pass
      if @proxy_from_env
        pass = proxy_uri&.password
        unescape(pass) if pass
      else
        @proxy_pass
      end
    end

    alias proxyaddr proxy_address   #:nodoc: obsolete
    alias proxyport proxy_port      #:nodoc: obsolete

    private

    def unescape(value)
      require 'cgi/util'
      CGI.unescape(value)
    end

    # without proxy, obsolete

    def conn_address # :nodoc:
      @ipaddr || address()
    end

    def conn_port # :nodoc:
      port()
    end

    def edit_path(path)
      if proxy?
        if path.start_with?("ftp://") || use_ssl?
          path
        else
          "http://#{addr_port}#{path}"
        end
      else
        path
      end
    end

    #
    # HTTP operations
    #

    public

    # Retrieves data from +path+ on the connected-to host which may be an
    # absolute path String or a URI to extract the path from.
    #
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
    # This method returns a Net::HTTPResponse object.
    #
    # If called with a block, yields each fragment of the
    # entity body in turn as a string as it is read from
    # the socket.  Note that in this case, the returned response
    # object will *not* contain a (meaningful) body.
    #
    # +dest+ argument is obsolete.
    # It still works but you must not use it.
    #
    # This method never raises an exception.
    #
    #     response = http.get('/index.html')
    #
    #     # using block
    #     File.open('result.txt', 'w') {|f|
    #       http.get('/~foo/') do |str|
    #         f.write str
    #       end
    #     }
    #
    def get(path, initheader = nil, dest = nil, &block) # :yield: +body_segment+
      res = nil
      request(Get.new(path, initheader)) {|r|
        r.read_body dest, &block
        res = r
      }
      res
    end

    # Gets only the header from +path+ on the connected-to host.
    # +header+ is a Hash like { 'Accept' => '*/*', ... }.
    #
    # This method returns a Net::HTTPResponse object.
    #
    # This method never raises an exception.
    #
    #     response = nil
    #     Net::HTTP.start('some.www.server', 80) {|http|
    #       response = http.head('/index.html')
    #     }
    #     p response['content-type']
    #
    def head(path, initheader = nil)
      request(Head.new(path, initheader))
    end

    # Posts +data+ (must be a String) to +path+. +header+ must be a Hash
    # like { 'Accept' => '*/*', ... }.
    #
    # This method returns a Net::HTTPResponse object.
    #
    # If called with a block, yields each fragment of the
    # entity body in turn as a string as it is read from
    # the socket.  Note that in this case, the returned response
    # object will *not* contain a (meaningful) body.
    #
    # +dest+ argument is obsolete.
    # It still works but you must not use it.
    #
    # This method never raises exception.
    #
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
      send_entity(path, data, initheader, dest, Post, &block)
    end

    # Sends a PATCH request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def patch(path, data, initheader = nil, dest = nil, &block) # :yield: +body_segment+
      send_entity(path, data, initheader, dest, Patch, &block)
    end

    def put(path, data, initheader = nil)   #:nodoc:
      request(Put.new(path, initheader), data)
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

    # Sends a GET request to the +path+.
    # Returns the response as a Net::HTTPResponse object.
    #
    # When called with a block, passes an HTTPResponse object to the block.
    # The body of the response will not have been read yet;
    # the block can process it using HTTPResponse#read_body,
    # if desired.
    #
    # Returns the response.
    #
    # This method never raises Net::* exceptions.
    #
    #     response = http.request_get('/index.html')
    #     # The entity body is already read in this case.
    #     p response['content-type']
    #     puts response.body
    #
    #     # Using a block
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

    # Sends a HEAD request to the +path+ and returns the response
    # as a Net::HTTPResponse object.
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

    # Sends a POST request to the +path+.
    #
    # Returns the response as a Net::HTTPResponse object.
    #
    # When called with a block, the block is passed an HTTPResponse
    # object.  The body of that response will not have been read yet;
    # the block can process it using HTTPResponse#read_body, if desired.
    #
    # Returns the response.
    #
    # This method never raises Net::* exceptions.
    #
    #     # example
    #     response = http.request_post('/cgi-bin/nice.rb', 'datadatadata...')
    #     p response.status
    #     puts response.body          # body is already read in this case
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
    # Also sends a DATA string if +data+ is given.
    #
    # Returns a Net::HTTPResponse object.
    #
    # This method never raises Net::* exceptions.
    #
    #    response = http.send_request('GET', '/index.html')
    #    puts response.body
    #
    def send_request(name, path, data = nil, header = nil)
      has_response_body = name != 'HEAD'
      r = HTTPGenericRequest.new(name,(data ? true : false),has_response_body,path,header)
      request r, data
    end

    # Sends an HTTPRequest object +req+ to the HTTP server.
    #
    # If +req+ is a Net::HTTP::Post or Net::HTTP::Put request containing
    # data, the data is also sent. Providing data for a Net::HTTP::Head or
    # Net::HTTP::Get request results in an ArgumentError.
    #
    # Returns an HTTPResponse object.
    #
    # When called with a block, passes an HTTPResponse object to the block.
    # The body of the response will not have been read yet;
    # the block can process it using HTTPResponse#read_body,
    # if desired.
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

    # Executes a request which uses a representation
    # and returns its body.
    def send_entity(path, data, initheader, dest, type, &block)
      res = nil
      request(type.new(path, initheader), data) {|r|
        r.read_body dest, &block
        res = r
      }
      res
    end

    IDEMPOTENT_METHODS_ = %w/GET HEAD PUT DELETE OPTIONS TRACE/ # :nodoc:

    def transport_request(req)
      count = 0
      begin
        begin_transport req
        res = catch(:response) {
          begin
            req.exec @socket, @curr_http_version, edit_path(req.path)
          rescue Errno::EPIPE
            # Failure when writing full request, but we can probably
            # still read the received response.
          end

          begin
            res = HTTPResponse.read_new(@socket)
            res.decode_content = req.decode_content
            res.body_encoding = @response_body_encoding
            res.ignore_eof = @ignore_eof
          end while res.kind_of?(HTTPInformation)

          res.uri = req.uri

          res
        }
        res.reading_body(@socket, req.response_body_permitted?) {
          yield res if block_given?
        }
      rescue Net::OpenTimeout
        raise
      rescue Net::ReadTimeout, IOError, EOFError,
             Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPIPE, Errno::ETIMEDOUT,
             # avoid a dependency on OpenSSL
             defined?(OpenSSL::SSL) ? OpenSSL::SSL::SSLError : IOError,
             Timeout::Error => exception
        if count < max_retries && IDEMPOTENT_METHODS_.include?(req.method)
          count += 1
          @socket.close if @socket
          debug "Conn close because of error #{exception}, and retry"
          retry
        end
        debug "Conn close because of error #{exception}"
        @socket.close if @socket
        raise
      end

      end_transport req, res
      res
    rescue => exception
      debug "Conn close because of error #{exception}"
      @socket.close if @socket
      raise exception
    end

    def begin_transport(req)
      if @socket.closed?
        connect
      elsif @last_communicated
        if @last_communicated + @keep_alive_timeout < Process.clock_gettime(Process::CLOCK_MONOTONIC)
          debug 'Conn close because of keep_alive_timeout'
          @socket.close
          connect
        elsif @socket.io.to_io.wait_readable(0) && @socket.eof?
          debug "Conn close because of EOF"
          @socket.close
          connect
        end
      end

      if not req.response_body_permitted? and @close_on_empty_response
        req['connection'] ||= 'close'
      end

      req.update_uri address, port, use_ssl?
      req['host'] ||= addr_port()
    end

    def end_transport(req, res)
      @curr_http_version = res.http_version
      @last_communicated = nil
      if @socket.closed?
        debug 'Conn socket closed'
      elsif not res.body and @close_on_empty_response
        debug 'Conn close'
        @socket.close
      elsif keep_alive?(req, res)
        debug 'Conn keep-alive'
        @last_communicated = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      else
        debug 'Conn close'
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
      addr = address
      addr = "[#{addr}]" if addr.include?(":")
      default_port = use_ssl? ? HTTP.https_default_port : HTTP.http_default_port
      default_port == port ? addr : "#{addr}:#{port}"
    end

    # Adds a message to debugging output
    def debug(msg)
      return unless @debug_output
      @debug_output << msg
      @debug_output << "\n"
    end

    alias_method :D, :debug
  end

end

require_relative 'http/exceptions'

require_relative 'http/header'

require_relative 'http/generic_request'
require_relative 'http/request'
require_relative 'http/requests'

require_relative 'http/response'
require_relative 'http/responses'

require_relative 'http/proxy_delta'

require_relative 'http/backward'
