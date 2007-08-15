require "rss/1.0"

module RSS

  CONTENT_PREFIX = 'content'
  CONTENT_URI = "http://purl.org/rss/1.0/modules/content/"

  RDF.install_ns(CONTENT_PREFIX, CONTENT_URI)

  module ContentModel

    extend BaseModel

    ELEMENTS = []

    def self.append_features(klass)
      super

      klass.install_must_call_validator(CONTENT_PREFIX, CONTENT_URI)
      %w(encoded).each do |name|
        klass.install_text_element(name, CONTENT_URI, "?",
                                   "#{CONTENT_PREFIX}_#{name}")
      end
    end
  end

  class RDF
    class Item; include ContentModel; end
  end

  prefix_size = CONTENT_PREFIX.size + 1
  ContentModel::ELEMENTS.uniq!
  ContentModel::ELEMENTS.each do |full_name|
    name = full_name[prefix_size..-1]
    BaseListener.install_get_text_element(CONTENT_URI, name, "#{full_name}=")
  end

end
