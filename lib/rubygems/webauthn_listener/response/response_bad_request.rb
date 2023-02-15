# frozen_string_literal: true
require_relative "../response"

class Gem::WebauthnListener::ResponseBadRequest < Gem::WebauthnListener::Response
  private

  def status
    "400 Bad Request"
  end

  def body
    "missing code parameter"
  end
end
