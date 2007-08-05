require "rss/rss"

module RSS
  module Maker
    MAKERS = {}

    class << self
      def make(version, &block)
        m = maker(version)
        raise UnsupportedMakerVersionError.new(version) if m.nil?
        m.make(&block)
      end

      def maker(version)
        MAKERS[version]
      end

      def add_maker(version, maker)
        MAKERS[version] = maker
      end

      def versions
        MAKERS.keys.uniq.sort
      end

      def makers
        MAKERS.values.uniq
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
require "rss/maker/syndication"
require "rss/maker/taxonomy"
require "rss/maker/trackback"
require "rss/maker/image"
require "rss/maker/itunes"
