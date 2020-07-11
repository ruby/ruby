# frozen_string_literal: true

begin
  require "openssl"
rescue LoadError => e
  raise unless e.path == 'openssl'
end
