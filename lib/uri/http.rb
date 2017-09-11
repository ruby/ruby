# frozen_string_literal: false
# = uri/http.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
# Revision:: $Id$
#
# See URI for general documentation
#

require 'uri/generic'

module URI

  #
  # The syntax of HTTP URIs is defined in RFC1738 section 3.3.
  #
  # Note that the Ruby URI library allows HTTP URLs containing usernames and
  # passwords. This is not legal as per the RFC, but used to be
  # supported in Internet Explorer 5 and 6, before the MS04-004 security
  # update. See <URL:http://support.microsoft.com/kb/834489>.
  #
  class HTTP < Generic
    # A Default port of 80 for URI::HTTP
    DEFAULT_PORT = 80

    # An Array of the available components for URI::HTTP
    COMPONENT = %i[
      scheme
      userinfo host port
      path
      query
      fragment
    ].freeze

    #
    # == Description
    #
    # Create a new URI::HTTP object from components, with syntax checking.
    #
    # The components accepted are userinfo, host, port, path, query and
    # fragment.
    #
    # The components should be provided either as an Array, or as a Hash
    # with keys formed by preceding the component names with a colon.
    #
    # If an Array is used, the components must be passed in the order
    # [userinfo, host, port, path, query, fragment].
    #
    # Example:
    #
    #     newuri = URI::HTTP.build(host: 'www.example.com', path: '/foo/bar')
    #
    #     newuri = URI::HTTP.build([nil, "www.example.com", nil, "/path",
    #       "query", 'fragment'])
    #
    # Currently, if passed userinfo components this method generates
    # invalid HTTP URIs as per RFC 1738.
    #
    def self.build(args)
      tmp = Util.make_components_hash(self, args)
      super(tmp)
    end

    #
    # == Description
    #
    # Returns the full path for an HTTP request, as required by Net::HTTP::Get.
    #
    # If the URI contains a query, the full path is URI#path + '?' + URI#query.
    # Otherwise, the path is simply URI#path.
    #
    # Example:
    #
    #     newuri = URI::HTTP.build(path: '/foo/bar', query: 'test=true')
    #     newuri.request_uri # => "/foo/bar?test=true"
    #
    def request_uri
      return unless @path

      url = @query ? "#@path?#@query" : @path.dup
      url.start_with?(?/.freeze) ? url : ?/ + url
    end
  end

  @@schemes['HTTP'] = HTTP

end
