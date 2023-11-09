# frozen_string_literal: true

require "net/http"

class Fail < Net::HTTP
  # Net::HTTP uses a @newimpl instance variable to decide whether
  # to use a legacy implementation. Since we are subclassing
  # Net::HTTP, we must set it
  @newimpl = true

  def request(req, body = nil, &block)
    raise(exception(req))
  end

  # Ensure we don't start a connect here
  def connect
  end

  def exception(req)
    Errno::ENETUNREACH.new("host down: Bundler spec artifice fail! #{req["PATH_INFO"]}")
  end
end

require_relative "helpers/artifice"

# Replace Net::HTTP with our failing subclass
Artifice.replace_net_http(::Fail)
