# Experimental

require "rss/1.0"

module RSS

  TAXO_PREFIX = "taxo"
  TAXO_NS = "http://purl.org/rss/1.0/modules/taxonomy/"

  Element.install_ns(TAXO_PREFIX, TAXO_NS)

  TAXO_ELEMENTS = []

  %w(link).each do |x|
    if const_defined? :Listener
      Listener.install_get_text_element(x, TAXO_NS, "#{TAXO_PREFIX}_#{x}=")
    end
    TAXO_ELEMENTS << "#{TAXO_PREFIX}_#{x}"
  end
    
  module TaxonomyModel
    attr_writer(*%w(title description creator subject publisher
                    contributor date format identifier source
                    language relation coverage rights).collect{|x| "#{TAXO_PREFIX}_#{x}"})
  end
  
  class Channel; extend TaxonomyModel;	end
  class Item; extend TaxonomyModel;	end
  class Image; extend TaxonomyModel;	end
  class TextInput; extend TaxonomyModel;	end
  
end
