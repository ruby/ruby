#
# erbhandler.rb -- ERBHandler Class
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: erbhandler.rb,v 1.25 2003/02/24 19:25:31 gotoyuzo Exp $

require 'webrick/httpservlet/abstract.rb'

require 'erb'

module WEBrick
  module HTTPServlet

    class ERBHandler < AbstractServlet
      def initialize(server, name)
        super(server, name)
        @script_filename = name
      end

      def do_GET(req, res)
        unless defined?(ERB)
          @logger.warn "#{self.class}: ERB not defined."
          raise HTTPStatus::Forbidden, "ERBHandler cannot work."
        end
        begin
          data = open(@script_filename){|io| io.read }
          res.body = evaluate(ERB.new(data), req, res)
          res['content-type'] =
            HTTPUtils::mime_type(@script_filename, @config[:MimeTypes])
        rescue StandardError => ex
          raise
        rescue Exception => ex
          @logger.error(ex)
          raise HTTPStatus::InternalServerError, ex.message
        end
      end

      alias do_POST do_GET

      private
      def evaluate(erb, servlet_request, servlet_response)
        Module.new.module_eval{
          meta_vars = servlet_request.meta_vars
          query = servlet_request.query
          erb.result(binding)
        }
      end
    end
  end
end
