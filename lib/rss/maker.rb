require "rss/rss"

module RSS

  module Maker

    MAKERS = {}
    
    class << self
      def make(version, &block)
        maker(version).make(&block)
      end

      def maker(version)
        MAKERS[version]
      end

      def add_maker(version, maker)
        MAKERS[version] = maker
      end

      def filename_to_version(filename)
        File.basename(filename, ".*")
      end
    end
  end
  
end

require "rss/maker/1.0"
require "rss/maker/2.0"
require "rss/maker/content"
require "rss/maker/dublincore"
require "rss/maker/syndication"
require "rss/maker/trackback"
