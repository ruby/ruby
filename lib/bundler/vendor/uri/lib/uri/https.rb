# frozen_string_literal: false
# = uri/https.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
#
# See Bundler::URI for general documentation
#

require_relative 'http'

module Bundler::URI

  # The default port for HTTPS URIs is 443, and the scheme is 'https:' rather
  # than 'http:'. Other than that, HTTPS URIs are identical to HTTP URIs;
  # see Bundler::URI::HTTP.
  class HTTPS < HTTP
    # A Default port of 443 for Bundler::URI::HTTPS
    DEFAULT_PORT = 443
  end

  register_scheme 'HTTPS', HTTPS
end
