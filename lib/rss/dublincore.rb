require "rss/1.0"

module RSS

  DC_PREFIX = 'dc'
  DC_URI = "http://purl.org/dc/elements/1.1/"
  
  RDF.install_ns(DC_PREFIX, DC_URI)

  module DublinCoreModel

    extend BaseModel

    ELEMENTS = []

    def self.append_features(klass)
      super
      
      klass.module_eval(<<-EOC, *get_file_and_line_from_caller(1))
        %w(title description creator subject publisher
            contributor type format identifier source
            language relation coverage rights).each do |x|
          install_text_element("\#{DC_PREFIX}_\#{x}")
        end

        %w(date).each do |x|
          install_date_element("\#{DC_PREFIX}_\#{x}", 'w3cdtf', x)
        end
      EOC
    end

    def dc_validate(tags)
      counter = {}
      ELEMENTS.each do |x|
        counter[x] = 0
      end

      tags.each do |tag|
        key = "#{DC_PREFIX}_#{tag}"
        raise UnknownTagError.new(tag, DC_URI)  unless counter.has_key?(key)
        counter[key] += 1
        raise TooMuchTagError.new(tag, tag_name) if counter[key] > 1
      end
    end

  end

  # For backward compatibility
  DublincoreModel = DublinCoreModel

  class RDF
    class Channel; include DublinCoreModel; end
    class Image; include DublinCoreModel; end
    class Item; include DublinCoreModel; end
    class Textinput; include DublinCoreModel; end
  end

  prefix_size = DC_PREFIX.size + 1
  DublinCoreModel::ELEMENTS.uniq!
  DublinCoreModel::ELEMENTS.each do |x|
    BaseListener.install_get_text_element(x[prefix_size..-1], DC_URI, "#{x}=")
  end

end
