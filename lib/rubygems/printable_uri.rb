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
    redact_credential

    self
  end

  def parsed_uri?
    @uri.is_a? URI::Generic
  end

  def credential_redacted?
    @credential_redacted
  end

  def original_password
    return unless parsed_uri?

    @original_uri.password
  end

  def to_s
    @uri.to_s
  end

  private

  def redact_credential
    return unless redactable_credential?

    if token?
      @uri.user = 'REDACTED'
    elsif oauth_basic?
      @uri.user = 'REDACTED'
    elsif password?
      @uri.password = 'REDACTED'
    end

    @credential_redacted = true
  end

  def redactable_credential?
    return false unless parsed_uri?

    password? || oauth_basic? || token?
  end

  def password?
    return false unless parsed_uri?

    !!@uri.password
  end

  def oauth_basic?
    return false unless parsed_uri?

    @uri.password == 'x-oauth-basic'
  end

  def token?
    return false unless parsed_uri?

    !@uri.user.nil? && @uri.password.nil?
  end
end
