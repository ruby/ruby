#
# = uri/http.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
# Revision:: $Id$
#

require 'uri/generic'

module URI

  #
  # RFC1738 section 3.3.
  #
  class HTTP < Generic
    DEFAULT_PORT = 80

    COMPONENT = [
      :scheme, 
      :userinfo, :host, :port, 
      :path, 
      :query, 
      :fragment
    ].freeze

    #
    # == Description
    #
    # Create a new URI::HTTP object from components of URI::HTTP with
    # check.  It is scheme, userinfo, host, port, path, query and
    # fragment. It provided by an Array of a Hash.
    #
    def self.build(args)
      tmp = Util::make_components_hash(self, args)
      return super(tmp)
    end

    #
    # == Description
    #
    # Create a new URI::HTTP object from ``generic'' components with no
    # check.
    #
    def initialize(*arg)
      super(*arg)
    end

    #
    # == Description
    #
    # Returns: path + '?' + query
    #
    def request_uri
      r = path_query
      if r[0] != ?/
        r = '/' + r
      end

      r
    end
  end

  @@schemes['HTTP'] = HTTP
end
