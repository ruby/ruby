=begin
= $RCSfile: ssl.rb,v $ -- Ruby-space definitions that completes C-space funcs for SSL

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
require "fcntl"

module OpenSSL
  module SSL
    module SocketForwarder
      def addr
        to_io.addr
      end

      def peeraddr
        to_io.peeraddr
      end

      def setsockopt(level, optname, optval)
        to_io.setsockopt(level, optname, optval)
      end

      def getsockopt(level, optname)
        to_io.getsockopt(level, optname)
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

    module Nonblock
      def initialize(*args)
        flag = File::NONBLOCK
        flag |= @io.fcntl(Fcntl::F_GETFL) if defined?(Fcntl::F_GETFL)
        @io.fcntl(Fcntl::F_SETFL, flag)
        super
      end
    end

    class SSLSocket
      include Buffering
      include SocketForwarder
      include Nonblock

      def post_connection_check(hostname)
        check_common_name = true
        cert = peer_cert
        cert.extensions.each{|ext|
          next if ext.oid != "subjectAltName"
          ext.value.split(/,\s+/).each{|general_name|
            if /\ADNS:(.*)/ =~ general_name
              check_common_name = false
              reg = Regexp.escape($1).gsub(/\\\*/, "[^.]+")
              return true if /\A#{reg}\z/i =~ hostname
            elsif /\AIP Address:(.*)/ =~ general_name
              check_common_name = false
              return true if $1 == hostname
            end
          }
        }
        if check_common_name
          cert.subject.to_a.each{|oid, value|
            if oid == "CN"
              reg = Regexp.escape(value).gsub(/\\\*/, "[^.]+")
              return true if /\A#{reg}\z/i =~ hostname
            end
          }
        end
        raise SSLError, "hostname not match"
      end
    end

    class SSLServer
      include SocketForwarder
      attr_accessor :start_immediately

      def initialize(svr, ctx)
        @svr = svr
        @ctx = ctx
        unless ctx.session_id_context
          session_id = OpenSSL::Digest::MD5.hexdigest($0)
          @ctx.session_id_context = session_id
        end
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
