=begin
= $RCSfile$ -- SSL/TLS enhancement for Net.

= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2001 GOTOU YUUZOU <gotoyuzo@notwork.org>
  All rights reserved.

= Licence
  This program is licenced under the same licence as Ruby.
  (See the file 'LICENCE'.)

= Requirements
  This program requires Net 1.2.0 or higher version.
  You can get it from RAA or Ruby's CVS repository.

= Version
  $Id$
  
  2001/11/06: Contiributed to Ruby/OpenSSL project.
=end

require 'net/protocol'
require 'forwardable'
require 'openssl'

module Net
  class SSLIO < InternetMessageIO
    extend Forwardable

    def_delegators(:@ssl_context,
                   :key=, :cert=, :key_file=, :cert_file=,
                   :ca_file=, :ca_path=,
                   :verify_mode=, :verify_callback=, :verify_depth=,
                   :timeout=, :cert_store=)

    def initialize(addr, port, otime = nil, rtime = nil, dout = nil)
      super
      @ssl_context = OpenSSL::SSL::SSLContext.new()
    end

    def ssl_connect()
      unless @ssl_context.verify_mode
        warn "warning: peer certificate won't be verified in this SSL session."
        @ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      @socket = OpenSSL::SSL::SSLSocket.new(@socket, @ssl_context)
      @socket.sync_close = true
      @socket.connect
    end

    def peer_cert
      @socket.peer_cert
    end
  end
end
