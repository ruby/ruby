# frozen_string_literal: true
require_relative "../response"

class Gem::WebauthnListener::ResponseMethodNotAllowed < Gem::WebauthnListener::Response
  private

  def status
    "405 Method Not Allowed"
  end

  def content
    <<~RESPONSE
      Allow: GET, OPTIONS
    RESPONSE
  end
end
