=begin
= $RCSfile$ -- Ruby-space predefined Digest subclasses

= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2002  Michal Rokos <m.rokos@sh.cvut.cz>
  All rights reserved.

= Licence
  This program is licenced under the same licence as Ruby.
  (See the file 'LICENCE'.)

= Version
  $Id$
=end

##
# Should we care what if somebody require this file directly?
#require 'openssl'

module OpenSSL
  module Digest

    %w(DSS DSS1 MD2 MD4 MD5 MDC2 RIPEMD160 SHA SHA1).each{|digest|
      eval(<<-EOD)
        class #{digest} < Digest
          def initialize(data=nil)
            super(\"#{digest}\", data)
          end

          def #{digest}::digest(data)
            Digest::digest(\"#{digest}\", data)
          end

          def #{digest}::hexdigest(data)
            Digest::hexdigest(\"#{digest}\", data)
          end
        end
      EOD
    }

  end # Digest
end # OpenSSL

