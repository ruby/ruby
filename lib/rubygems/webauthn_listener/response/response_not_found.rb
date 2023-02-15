# frozen_string_literal: true
require_relative "../response"

class Gem::WebauthnListener::ResponseNotFound < Gem::WebauthnListener::Response
  private

  def status
    "404 Not Found"
  end
end
