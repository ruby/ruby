require "rss/rss"

module RSS

  module Maker

    MAKERS = {}
    
    class << self
      def make(version, modules=[], &block)
        prefix = "rss/maker"
        require "#{prefix}/#{version}"
        modules.each do |mod|
          require "#{prefix}/#{mod}"
        end
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
