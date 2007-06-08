=begin
= $RCSfile$ -- PKCS7

= Licence
  This program is licenced under the same licence as Ruby.
  (See the file 'LICENCE'.)

= Version
  $Id: digest.rb 12148 2007-04-05 05:59:22Z technorama $
=end

module OpenSSL
  class PKCS7
    # This class is only provided for backwards compatibility.  Use OpenSSL::PKCS7 in the future.
    class PKCS7 < PKCS7
      def initialize(*args)
        super(*args)

        warn("Warning: OpenSSL::PKCS7::PKCS7 is deprecated after Ruby 1.9; use OpenSSL::PKCS7 instead")
      end
    end

  end # PKCS7
end # OpenSSL

