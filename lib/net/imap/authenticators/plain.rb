# frozen_string_literal: true

# Authenticator for the "+PLAIN+" SASL mechanism.  See Net::IMAP#authenticate.
#
# See RFC4616[https://tools.ietf.org/html/rfc4616] for the specification.
class Net::IMAP::PlainAuthenticator

  def process(data)
    return "#@authzid\0#@username\0#@password"
  end

  NULL = -"\0".b

  private

  # +username+ is the authentication identity, the identity whose +password+ is
  # used.  +username+ is referred to as +authcid+ by
  # RFC4616[https://tools.ietf.org/html/rfc4616].
  #
  # +authzid+ is the authorization identity (identity to act as).  It can
  # usually be left blank. When +authzid+ is left blank (nil or empty string)
  # the server will derive an identity from the credentials and use that as the
  # authorization identity.
  def initialize(username, password, authzid: nil)
    raise ArgumentError, "username contains NULL" if username&.include?(NULL)
    raise ArgumentError, "password contains NULL" if password&.include?(NULL)
    raise ArgumentError, "authzid  contains NULL" if authzid&.include?(NULL)
    @username = username
    @password = password
    @authzid  = authzid
  end

  Net::IMAP.add_authenticator "PLAIN", self
end
