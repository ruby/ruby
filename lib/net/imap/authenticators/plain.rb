# frozen_string_literal: true

# Authenticator for the "+PLAIN+" SASL mechanism.  See Net::IMAP#authenticate.
#
# See RFC4616[https://tools.ietf.org/html/rfc4616] for the specification.
class Net::IMAP::PlainAuthenticator
  def process(data)
    return "\0#{@user}\0#{@password}"
  end

  private

  def initialize(user, password)
    @user = user
    @password = password
  end

  Net::IMAP.add_authenticator "PLAIN", self
end
