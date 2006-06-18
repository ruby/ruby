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
      
      klass.module_eval(<<-EOC, *get_file_and_line_from_caller(1))
        %w(encoded).each do |name|
          install_text_element("\#{CONTENT_PREFIX}_\#{name}")
        end
      EOC
    end

    def content_validate(ignore_unknown_element, tags, uri)
      counter = {}
      ELEMENTS.each do |name|
        counter[name] = 0
      end

      tags.each do |tag|
        key = "#{CONTENT_PREFIX}_#{tag}"
        if !ignore_unknown_element and !counter.has_key?(key)
          raise UnknownTagError.new(tag, CONTENT_URI)
        end
        counter[key] += 1
        raise TooMuchTagError.new(tag, tag_name) if counter[key] > 1
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
