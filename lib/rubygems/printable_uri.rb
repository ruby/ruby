# frozen_string_literal: true

require 'uri'
require_relative 'uri_parser'

class Gem::PrintableUri
  def self.parse_uri(uri)
    new(uri).parse_uri
  end

  def initialize(original_uri)
    @credential_redacted = false
    @original_uri = original_uri
  end

  def parse_uri
    @original_uri = Gem::UriParser.parse_uri(@original_uri)
    @uri = @original_uri.clone
    redact_credential if valid_uri?

    self
  end

  def valid_uri?
    @uri.is_a? URI::Generic
  end

  def credential_redacted?
    @credential_redacted
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
      @credential_redacted = true
    elsif oauth_basic?
      @uri.user = 'REDACTED'
      @credential_redacted = true
    elsif password?
      @uri.password = 'REDACTED'
      @credential_redacted = true
    end
  end

  def redactable_credential?
    password? || oauth_basic? || token?
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
