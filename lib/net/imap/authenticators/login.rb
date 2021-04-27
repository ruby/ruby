# frozen_string_literal: true

# Authenticator for the "+LOGIN+" SASL mechanism.  See Net::IMAP#authenticate.
#
# == Deprecated
#
# The {SASL mechanisms
# registry}[https://www.iana.org/assignments/sasl-mechanisms/sasl-mechanisms.xhtml]
# marks "LOGIN" as obsoleted in favor of "PLAIN".  See also
# {draft-murchison-sasl-login}[https://www.iana.org/go/draft-murchison-sasl-login].
class Net::IMAP::LoginAuthenticator
  def process(data)
    case @state
    when STATE_USER
      @state = STATE_PASSWORD
      return @user
    when STATE_PASSWORD
      return @password
    end
  end

  private

  STATE_USER = :USER
  STATE_PASSWORD = :PASSWORD

  def initialize(user, password)
    @user = user
    @password = password
    @state = STATE_USER
  end

  Net::IMAP.add_authenticator "LOGIN", self
end
