require 'uri/ldap'

module URI

  # The default port for LDAPS URIs is 636, and the scheme is 'ldaps:' rather
  # than 'ldap:'. Other than that, LDAPS URIs are identical to LDAP URIs;
  # see URI::LDAP.
  class LDAPS < LDAP
    DEFAULT_PORT = 636
  end
  @@schemes['LDAPS'] = LDAPS
end
