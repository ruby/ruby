# frozen_string_literal: true

begin
  require "rubygems/vendored_net_http"
rescue LoadError
  require "net/http"
  Gem::Net = Net
end
