#
# httpservlet.rb -- HTTPServlet Module
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2000 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: abstract.rb,v 1.24 2003/07/11 11:16:46 gotoyuzo Exp $

require 'thread'

require 'webrick/htmlutils'
require 'webrick/httputils'
require 'webrick/httpstatus'

module WEBrick
  module HTTPServlet
    class HTTPServletError < StandardError; end

    class AbstractServlet
      def self.get_instance(config, *options)
        self.new(config, *options)
      end

      def initialize(server, *options)
        @server = @config = server
        @logger = @server[:Logger]
        @options = options
      end

      def service(req, res)
        method_name = "do_" + req.request_method.gsub(/-/, "_")
        if respond_to?(method_name)
          __send__(method_name, req, res)
        else
          raise HTTPStatus::MethodNotAllowed,
                "unsupported method `#{req.request_method}'."
        end
      end

      def do_GET(req, res)
        raise HTTPStatus::NotFound, "not found."
      end

      def do_HEAD(req, res)
        do_GET(req, res)
      end

      def do_OPTIONS(req, res)
        m = self.methods.grep(/^do_[A-Z]+$/)
        m.collect!{|i| i.sub(/do_/, "") }
        m.sort!
        res["allow"] = m.join(",")
      end

      private

      def redirect_to_directory_uri(req, res)
        if req.path[-1] != ?/
          location = WEBrick::HTTPUtils.escape_path(req.path + "/")
          if req.query_string && req.query_string.bytesize > 0
            location << "?" << req.query_string
          end
          res.set_redirect(HTTPStatus::MovedPermanently, location)
        end
      end
    end

  end
end
