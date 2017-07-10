# frozen_string_literal: true
# We forcibly require OpenSSL, because net/http/persistent will only autoload
# it. On some Rubies, autoload fails but explicit require succeeds.
begin
  require "openssl"
rescue LoadError
  # some Ruby builds don't have OpenSSL
end
module Bundler
  module Persistent
    module Net
      module HTTP
      end
    end
  end
end
require "bundler/vendor/net-http-persistent/lib/net/http/persistent"
