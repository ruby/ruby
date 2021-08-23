# frozen_string_literal: true

require_relative 'uri_parser'

class Gem::PrintableUri
  def self.parse_uri(uri)
    printable_uri = new(uri)
    printable_uri.parse_uri

    printable_uri
  end

  def initialize(original_uri)
    @original_uri = original_uri
  end

  def parse_uri
    @original_uri = Gem::UriParser.parse_uri(@original_uri)
    @uri = @original_uri.clone
    redact_credential if valid_uri?
  end

  def valid_uri?
    @uri.respond_to?(:user) &&
      @uri.respond_to?(:user=) &&
      @uri.respond_to?(:password) &&
      @uri.respond_to?(:password=)
  end

  def original_password
    @original_uri.password
  end

  def to_s
    @uri.to_s
  end

  private

  def redact_credential
    if token?
      @uri.user = 'REDACTED'
    elsif oauth_basic?
      @uri.user = 'REDACTED'
    elsif password?
      @uri.password = 'REDACTED'
    end
  end

  def password?
    !!@uri.password
  end

  def oauth_basic?
    @uri.password == 'x-oauth-basic'
  end

  def token?
    !@uri.user.nil? && @uri.password.nil?
  end
end
