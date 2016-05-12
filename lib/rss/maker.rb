# frozen_string_literal: false
require "rss/rss"

module RSS
  ##
  #
  # Provides a set of builders for various RSS objects
  #
  # * Feeds
  #   * RSS 0.91
  #   * RSS 1.0
  #   * RSS 2.0
  #   * Atom 1.0
  #
  # * Elements
  #   * Atom::Entry

  module Maker

    # Collection of supported makers
    MAKERS = {}

    class << self
      # Builder for an RSS object
      # Creates an object of the type passed in +args+
      #
      # Executes the +block+ to populate elements of the created RSS object
      def make(version, &block)
        self[version].make(&block)
      end

      # Returns the maker for the +version+
      def [](version)
        maker_info = maker(version)
        raise UnsupportedMakerVersionError.new(version) if maker_info.nil?
        maker_info[:maker]
      end

      # Adds a maker to the set of supported makers
      def add_maker(version, normalized_version, maker)
        MAKERS[version] = {:maker => maker, :version => normalized_version}
      end

      # Returns collection of supported maker versions
      def versions
        MAKERS.keys.uniq.sort
      end

      # Returns collection of supported makers
      def makers
        MAKERS.values.collect { |info| info[:maker] }.uniq
      end

      # Returns true if the version is supported
      def supported?(version)
        versions.include?(version)
      end

      private
      # Can I remove this method?
      def maker(version)
        MAKERS[version]
      end
    end
  end
end

require "rss/maker/1.0"
require "rss/maker/2.0"
require "rss/maker/feed"
require "rss/maker/entry"
require "rss/maker/content"
require "rss/maker/dublincore"
require "rss/maker/slash"
require "rss/maker/syndication"
require "rss/maker/taxonomy"
require "rss/maker/trackback"
require "rss/maker/image"
require "rss/maker/itunes"
