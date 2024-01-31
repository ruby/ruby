# frozen_string_literal: true

begin
  require "rubygems/vendored_timeout"
rescue LoadError
  require "timeout"
  Gem::Timeout = Timeout
end
