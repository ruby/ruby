=begin
= $RCSfile$ -- Ruby-space definitions that completes C-space funcs for SSL

= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2001 GOTOU YUUZOU <gotoyuzo@notwork.org>
  All rights reserved.

= Licence
  This program is licenced under the same licence as Ruby.
  (See the file 'LICENCE'.)

= Version
  $Id$
=end

require "openssl"
require "openssl/buffering"

module OpenSSL
  module SSL
    module SocketForwarder
      def addr
        to_io.addr
      end

      def peeraddr
        to_io.peeraddr
      end

      def getsockopt(level, optname, optval)
        to_io.setsockopt(level, optname, optval)
      end

      def setsockopt(level, optname)
        to_io.setsockopt(level, optname)
      end

      def fcntl(*args)
        to_io.fcntl(*args)
      end

      def closed?
        to_io.closed?
      end

      def do_not_reverse_lookup=(flag)
        to_io.do_not_reverse_lookup = flag
      end
    end

    class SSLSocket
      include Buffering
      include SocketForwarder
    end

    class SSLServer
      include SocketForwarder
      attr_accessor :start_immediately

      def initialize(svr, ctx)
        @svr = svr
        @ctx = ctx
        @start_immediately = true
      end

      def to_io
        @svr
      end

      def listen(backlog=5)
        @svr.listen(backlog)
      end

      def accept
        sock = @svr.accept
        begin
          ssl = OpenSSL::SSL::SSLSocket.new(sock, @ctx)
          ssl.sync_close = true
          ssl.accept if @start_immediately
          ssl
        rescue SSLError => ex
          sock.close
          raise ex
        end
      end

      def close
        @svr.close
      end
    end
  end
end
