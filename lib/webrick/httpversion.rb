#--
# HTTPVersion.rb -- presentation of HTTP version
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: httpversion.rb,v 1.5 2002/09/21 12:23:37 gotoyuzo Exp $

module WEBrick

  ##
  # Represents an HTTP protocol version

  class HTTPVersion
    include Comparable

    ##
    # The major protocol version number

    attr_accessor :major

    ##
    # The minor protocol version number

    attr_accessor :minor

    ##
    # Converts +version+ into an HTTPVersion

    def self.convert(version)
      version.is_a?(self) ? version : new(version)
    end

    ##
    # Creates a new HTTPVersion from +version+.

    def initialize(version)
      case version
      when HTTPVersion
        @major, @minor = version.major, version.minor
      when String
        if /^(\d+)\.(\d+)$/ =~ version
          @major, @minor = $1.to_i, $2.to_i
        end
      end
      if @major.nil? || @minor.nil?
        raise ArgumentError,
          format("cannot convert %s into %s", version.class, self.class)
      end
    end

    ##
    # Compares this version with +other+ according to the HTTP specification
    # rules.

    def <=>(other)
      unless other.is_a?(self.class)
        other = self.class.new(other)
      end
      if (ret = @major <=> other.major) == 0
        return @minor <=> other.minor
      end
      return ret
    end

    ##
    # The HTTP version as show in the HTTP request and response.  For example,
    # "1.1"

    def to_s
      format("%d.%d", @major, @minor)
    end
  end
end
