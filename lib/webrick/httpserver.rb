#
# httpserver.rb -- HTTPServer Class
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2000, 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: httpserver.rb,v 1.63 2002/10/01 17:16:32 gotoyuzo Exp $

require 'webrick/server'
require 'webrick/httputils'
require 'webrick/httpstatus'
require 'webrick/httprequest'
require 'webrick/httpresponse'
require 'webrick/httpservlet'
require 'webrick/accesslog'

module WEBrick
  class HTTPServerError < ServerError; end

  class HTTPServer < ::WEBrick::GenericServer
    def initialize(config={}, default=Config::HTTP)
      super
      @http_version = HTTPVersion::convert(@config[:HTTPVersion])

      @mount_tab = MountTable.new
      if @config[:DocumentRoot]
        mount("/", HTTPServlet::FileHandler, @config[:DocumentRoot],
              @config[:DocumentRootOptions])
      end

      unless @config[:AccessLog]
        basic_log = BasicLog::new
        @config[:AccessLog] = [
          [ basic_log, AccessLog::COMMON_LOG_FORMAT ],
          [ basic_log, AccessLog::REFERER_LOG_FORMAT ]
        ]
      end
    end

    def run(sock)
      while true 
        res = HTTPResponse.new(@config)
        req = HTTPRequest.new(@config)
        begin
          req.parse(sock)
          res.request_method = req.request_method
          res.request_uri = req.request_uri
          res.request_http_version = req.http_version
          if handler = @config[:RequestHandler]
            handler.call(req, res)
          end
          service(req, res)
        rescue HTTPStatus::EOFError, HTTPStatus::RequestTimeout => ex
          res.set_error(ex)
        rescue HTTPStatus::Error => ex
          res.set_error(ex)
        rescue HTTPStatus::Status => ex
          res.status = ex.code
        rescue StandardError, NameError => ex # for Ruby 1.6
          @logger.error(ex)
          res.set_error(ex, true)
        ensure
          if req.request_line
            req.fixup()
            res.send_response(sock)
            access_log(@config, req, res)
          end
        end
        break if @http_version < "1.1"
        break unless req.keep_alive?
        break unless res.keep_alive?
      end
    end

    def service(req, res)
      if req.unparsed_uri == "*"
        if req.request_method == "OPTIONS"
          do_OPTIONS(req, res)
          raise HTTPStatus::OK
        end
        raise HTTPStatus::NotFound, "`#{req.unparsed_uri}' not found."
      end

      servlet, options, script_name, path_info = search_servlet(req.path)
      raise HTTPStatus::NotFound, "`#{req.path}' not found." unless servlet
      req.script_name = script_name
      req.path_info = path_info
      si = servlet.get_instance(self, *options)
      @logger.debug(format("%s is invoked.", si.class.name))
      si.service(req, res)
    end

    def do_OPTIONS(req, res)
      res["allow"] = "GET,HEAD,POST,OPTIONS"
    end

    def mount(dir, servlet, *options)
      @logger.debug(sprintf("%s is mounted on %s.", servlet.inspect, dir))
      @mount_tab[dir] = [ servlet, options ]
    end

    def mount_proc(dir, proc=nil, &block)
      proc ||= block
      raise HTTPServerError, "must pass a proc or block" unless proc
      mount(dir, HTTPServlet::ProcHandler.new(proc))
    end

    def unmount(dir)
      @logger.debug(sprintf("unmount %s.", inspect, dir))
      @mount_tab.delete(dir)
    end
    alias umount unmount

    def search_servlet(path)
      script_name, path_info = @mount_tab.scan(path)
      servlet, options = @mount_tab[script_name]
      if servlet
        [ servlet, options, script_name, path_info ]
      end
    end

    def access_log(config, req, res)
      param = AccessLog::setup_params(config, req, res)
      level = Log::INFO
      @config[:AccessLog].each{|logger, fmt|
        logger.log(level, AccessLog::format(fmt, param))
      }
    end

    class MountTable
      def initialize
        @tab = Hash.new
        compile
      end

      def [](dir)
        dir = normalize(dir)
        @tab[dir]
      end

      def []=(dir, val)
        dir = normalize(dir)
        @tab[dir] = val
        compile
        val
      end

      def delete(dir)
        dir = normalize(dir)
        res = @tab.delete(dir)
        compile
        res
      end

      def scan(path)
        @scanner =~ path
        [ $&, $' ]
      end

      private

      def compile
        k = @tab.keys
        k.sort!
        k.reverse!
        k.collect!{|path| Regexp.escape(path) }
        @scanner = Regexp.new("^(" + k.join("|") +")(?=/|$)")
      end

      def normalize(dir)
        ret = dir ? dir.dup : ""
        ret.sub!(%r|/+$|, "")
        ret
      end
    end
  end
end
