#
# $Id$
#
# Copyright (c) 2001 akira yamada <akira@ruby-lang.org>
# You can redistribute it and/or modify it under the same term as Ruby.
#

require 'uri/generic'

module URI

=begin

== URI::HTTP

=== Super Class

((<URI::Generic>))

=end

  # RFC1738 section 3.3.
  class HTTP < Generic
    DEFAULT_PORT = 80

    COMPONENT = [
      :scheme, 
      :userinfo, :host, :port, 
      :path, 
      :query, 
      :fragment
    ].freeze

=begin

=== Class Methods

--- URI::HTTP::build
    Create a new URI::HTTP object from components of URI::HTTP with
    check.  It is scheme, userinfo, host, port, path, query and
    fragment. It provided by an Array of a Hash.

--- URI::HTTP::new
    Create a new URI::HTTP object from ``generic'' components with no
    check.

=end

    def self.build(args)
      tmp = Util::make_components_hash(self, args)
      return super(tmp)
    end

    def initialize(*arg)
      super(*arg)
    end

=begin

=== Instance Methods

--- URI::HTTP#request_uri

=end
    def request_uri
      r = path_query
      if r[0] != ?/
	r = '/' + r
      end

      r
    end
  end # HTTP

  @@schemes['HTTP'] = HTTP
end # URI
