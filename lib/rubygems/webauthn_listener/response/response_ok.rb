# frozen_string_literal: true
require_relative "../response"

class Gem::WebauthnListener::ResponseOk < Gem::WebauthnListener::Response
  private

  def status
    "200 OK"
  end

  def add_access_control_headers?
    true
  end

  def body
    "success"
  end
end
