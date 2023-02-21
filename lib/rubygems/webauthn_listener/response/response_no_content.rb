# frozen_string_literal: true
require_relative "../response"

class Gem::WebauthnListener::ResponseNoContent < Gem::WebauthnListener::Response
  private

  def status
    "204 No Content"
  end
end
