require "rss/rss"

module RSS
  module Maker
    MAKERS = {}

    class << self
      def make(version, &block)
        maker_info = self[version]
        maker_info[:maker].make(maker_info[:version], &block)
      end

      def [](version)
        maker_info = maker(version)
        raise UnsupportedMakerVersionError.new(version) if maker_info.nil?
        maker_info
      end

      def add_maker(version, normalized_version, maker)
        MAKERS[version] = {:maker => maker, :version => normalized_version}
      end

      def versions
        MAKERS.keys.uniq.sort
      end

      def makers
        MAKERS.values.collect {|info| info[:maker]}.uniq
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
