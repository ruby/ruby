require "rss/atom"
require "rss/dublincore"

module RSS
  module Atom
    Feed.install_ns(DC_PREFIX, DC_URI)

    class Feed
      include DublinCoreModel
      class Entry; include DublinCoreModel; end
    end

    class Entry
      include DublinCoreModel
    end
  end
end
