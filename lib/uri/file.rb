# frozen_string_literal: false
# = uri/http.rb
#
# Author:: Roberto Polli <robipolli@gmail.com>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
# Revision:: $Id$
#
# See URI for general documentation
#

require 'uri/generic'

module URI

  #
  # The syntax of FILE URIs is defined in RFC8089 section 2.
  #
  class FILE < Generic
    #
    # == Description
    #
    # Create a new URI::FILE using the Generic initializer.
    #
    # To serialize the uri in the traditional form and not in 
    # the minimal one (see https://tools.ietf.org/html/rfc8089#appendix-B)
    # set host to blank.
    #
    def self.initialize(*args)
      super(*args)
      @host = "" if @host.nil?
    end
  end

  @@schemes['HTTP'] = HTTP

end
