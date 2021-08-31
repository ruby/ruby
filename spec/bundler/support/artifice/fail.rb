# frozen_string_literal: true

require "net/http"

# We can't use artifice here because it uses rack

module Artifice; end # for < 2.0, Net::HTTP::Persistent::SSLReuse

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
    name = ENV.fetch("BUNDLER_SPEC_EXCEPTION") { "Errno::ENETUNREACH" }
    const = name.split("::").reduce(Object) {|mod, sym| mod.const_get(sym) }
    const.new("host down: Bundler spec artifice fail! #{req["PATH_INFO"]}")
  end
end

# Replace Net::HTTP with our failing subclass
::Net.class_eval do
  remove_const(:HTTP)
  const_set(:HTTP, ::Fail)
end
