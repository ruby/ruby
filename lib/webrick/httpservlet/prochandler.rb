# frozen_string_literal: false
#
# prochandler.rb -- ProcHandler Class
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: prochandler.rb,v 1.7 2002/09/21 12:23:42 gotoyuzo Exp $

require 'webrick/httpservlet/abstract.rb'

module WEBrick
  module HTTPServlet

    ##
    # Mounts a proc at a path that accepts a request and response.
    #
    # Instead of mounting this servlet with WEBrick::HTTPServer#mount use
    # WEBrick::HTTPServer#mount_proc:
    #
    #   server.mount_proc '/' do |req, res|
    #     res.body = 'it worked!'
    #     res.status = 200
    #   end

    class ProcHandler < AbstractServlet
      # :stopdoc:
      def get_instance(server, *options)
        self
      end

      def initialize(proc)
        @proc = proc
      end

      def do_GET(request, response)
        @proc.call(request, response)
      end

      alias do_POST do_GET
      # :startdoc:
    end

  end
end
