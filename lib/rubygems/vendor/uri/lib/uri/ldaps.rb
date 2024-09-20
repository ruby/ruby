# frozen_string_literal: false
# = uri/ldap.rb
#
# License:: You can redistribute it and/or modify it under the same term as Ruby.
#
# See Gem::URI for general documentation
#

require_relative 'ldap'

module Gem::URI

  # The default port for LDAPS URIs is 636, and the scheme is 'ldaps:' rather
  # than 'ldap:'. Other than that, LDAPS URIs are identical to LDAP URIs;
  # see Gem::URI::LDAP.
  class LDAPS < LDAP
    # A Default port of 636 for Gem::URI::LDAPS
    DEFAULT_PORT = 636
  end

  register_scheme 'LDAPS', LDAPS
end
