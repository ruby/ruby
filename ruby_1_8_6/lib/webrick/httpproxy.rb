#
# httpproxy.rb -- HTTPProxy Class
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2002 GOTO Kentaro
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: httpproxy.rb,v 1.18 2003/03/08 18:58:10 gotoyuzo Exp $
# $kNotwork: straw.rb,v 1.3 2002/02/12 15:13:07 gotoken Exp $

require "webrick/httpserver"
require "net/http"

Net::HTTP::version_1_2 if RUBY_VERSION < "1.7"

module WEBrick
  NullReader = Object.new
  class << NullReader
    def read(*args)
      nil
    end
    alias gets read
  end

  class HTTPProxyServer < HTTPServer
    def initialize(config)
      super
      c = @config
      @via = "#{c[:HTTPVersion]} #{c[:ServerName]}:#{c[:Port]}"
    end

    def service(req, res)
      if req.request_method == "CONNECT"
        proxy_connect(req, res)
      elsif req.unparsed_uri =~ %r!^http://!
        proxy_service(req, res)
      else
        super(req, res)
      end
    end

    def proxy_auth(req, res)
      if proc = @config[:ProxyAuthProc]
        proc.call(req, res)
      end
      req.header.delete("proxy-authorization")
    end

    # Some header fields shuold not be transfered.
    HopByHop = %w( connection keep-alive proxy-authenticate upgrade
                   proxy-authorization te trailers transfer-encoding )
    ShouldNotTransfer = %w( set-cookie proxy-connection )
    def split_field(f) f ? f.split(/,\s+/).collect{|i| i.downcase } : [] end

    def choose_header(src, dst)
      connections = split_field(src['connection'])
      src.each{|key, value|
        key = key.downcase
        if HopByHop.member?(key)          || # RFC2616: 13.5.1
           connections.member?(key)       || # RFC2616: 14.10
           ShouldNotTransfer.member?(key)    # pragmatics
          @logger.debug("choose_header: `#{key}: #{value}'")
          next
        end
        dst[key] = value
      }
    end

    # Net::HTTP is stupid about the multiple header fields.
    # Here is workaround:
    def set_cookie(src, dst)
      if str = src['set-cookie']
        cookies = []
        str.split(/,\s*/).each{|token|
          if /^[^=]+;/o =~ token
            cookies[-1] << ", " << token
          elsif /=/o =~ token
            cookies << token
          else
            cookies[-1] << ", " << token
          end
        }
        dst.cookies.replace(cookies)
      end
    end

    def set_via(h)
      if @config[:ProxyVia]
        if  h['via']
          h['via'] << ", " << @via
        else
          h['via'] = @via
        end
      end
    end

    def proxy_uri(req, res)
      @config[:ProxyURI]
    end

    def proxy_service(req, res)
      # Proxy Authentication
      proxy_auth(req, res)      

      # Create Request-URI to send to the origin server
      uri  = req.request_uri
      path = uri.path.dup
      path << "?" << uri.query if uri.query

      # Choose header fields to transfer
      header = Hash.new
      choose_header(req, header)
      set_via(header)

      # select upstream proxy server
      if proxy = proxy_uri(req, res)
        proxy_host = proxy.host
        proxy_port = proxy.port
        if proxy.userinfo
          credentials = "Basic " + [proxy.userinfo].pack("m*")
          credentials.chomp!
          header['proxy-authorization'] = credentials
        end
      end

      response = nil
      begin
        http = Net::HTTP.new(uri.host, uri.port, proxy_host, proxy_port)
        http.start{
          if @config[:ProxyTimeout]
            ##################################   these issues are 
            http.open_timeout = 30   # secs  #   necessary (maybe bacause
            http.read_timeout = 60   # secs  #   Ruby's bug, but why?)
            ##################################
          end
          case req.request_method
          when "GET"  then response = http.get(path, header)
          when "POST" then response = http.post(path, req.body || "", header)
          when "HEAD" then response = http.head(path, header)
          else
            raise HTTPStatus::MethodNotAllowed,
              "unsupported method `#{req.request_method}'."
          end
        }
      rescue => err
        logger.debug("#{err.class}: #{err.message}")
        raise HTTPStatus::ServiceUnavailable, err.message
      end
  
      # Persistent connction requirements are mysterious for me.
      # So I will close the connection in every response.
      res['proxy-connection'] = "close"
      res['connection'] = "close"

      # Convert Net::HTTP::HTTPResponse to WEBrick::HTTPProxy
      res.status = response.code.to_i
      choose_header(response, res)
      set_cookie(response, res)
      set_via(res)
      res.body = response.body

      # Process contents
      if handler = @config[:ProxyContentHandler]
        handler.call(req, res)
      end
    end

    def proxy_connect(req, res)
      # Proxy Authentication
      proxy_auth(req, res)

      ua = Thread.current[:WEBrickSocket]  # User-Agent
      raise HTTPStatus::InternalServerError,
        "[BUG] cannot get socket" unless ua

      host, port = req.unparsed_uri.split(":", 2)
      # Proxy authentication for upstream proxy server
      if proxy = proxy_uri(req, res)
        proxy_request_line = "CONNECT #{host}:#{port} HTTP/1.0"
        if proxy.userinfo
          credentials = "Basic " + [proxy.userinfo].pack("m*")
          credentials.chomp!
        end
        host, port = proxy.host, proxy.port
      end

      begin
        @logger.debug("CONNECT: upstream proxy is `#{host}:#{port}'.")
        os = TCPSocket.new(host, port)     # origin server

        if proxy
          @logger.debug("CONNECT: sending a Request-Line")
          os << proxy_request_line << CRLF
          @logger.debug("CONNECT: > #{proxy_request_line}")
          if credentials
            @logger.debug("CONNECT: sending a credentials")
            os << "Proxy-Authorization: " << credentials << CRLF
          end
          os << CRLF
          proxy_status_line = os.gets(LF)
          @logger.debug("CONNECT: read a Status-Line form the upstream server")
          @logger.debug("CONNECT: < #{proxy_status_line}")
          if %r{^HTTP/\d+\.\d+\s+200\s*} =~ proxy_status_line
            while line = os.gets(LF)
              break if /\A(#{CRLF}|#{LF})\z/om =~ line
            end
          else
            raise HTTPStatus::BadGateway
          end
        end
        @logger.debug("CONNECT #{host}:#{port}: succeeded")
        res.status = HTTPStatus::RC_OK
      rescue => ex
        @logger.debug("CONNECT #{host}:#{port}: failed `#{ex.message}'")
        res.set_error(ex)
        raise HTTPStatus::EOFError
      ensure
        if handler = @config[:ProxyContentHandler]
          handler.call(req, res)
        end
        res.send_response(ua)
        access_log(@config, req, res)

        # Should clear request-line not to send the sesponse twice.
        # see: HTTPServer#run
        req.parse(NullReader) rescue nil
      end

      begin
        while fds = IO::select([ua, os])
          if fds[0].member?(ua)
            buf = ua.sysread(1024);
            @logger.debug("CONNECT: #{buf.size} byte from User-Agent")
            os.syswrite(buf)
          elsif fds[0].member?(os)
            buf = os.sysread(1024);
            @logger.debug("CONNECT: #{buf.size} byte from #{host}:#{port}")
            ua.syswrite(buf)
          end
        end
      rescue => ex
        os.close
        @logger.debug("CONNECT #{host}:#{port}: closed")
      end

      raise HTTPStatus::EOFError
    end

    def do_OPTIONS(req, res)
      res['allow'] = "GET,HEAD,POST,OPTIONS,CONNECT"
    end
  end
end
