# frozen_string_literal: true

begin
  require "rubygems/net/http"
rescue LoadError
  require "net/http"
  Gem::Net = Net
end
