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

require 'openssl/buffering'

module OpenSSL
  module SSL
    class SSLSocket
      include Buffering

      def addr
        @io.addr
      end

      def peeraddr
        @io.peeraddr
      end

      def getsockopt(level, optname, optval)
        @io.setsockopt(level, optname, optval)
      end

      def setsockopt(level, optname)
        @io.setsockopt(level, optname)
      end

      def fcntl(*args)
        @io.fcntl(*args)
      end

      def closed?
        @io.closed?
      end
    end
  end
end
