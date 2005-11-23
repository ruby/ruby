require "rss/1.0"
require "rss/dublincore"

module RSS

  TAXO_PREFIX = "taxo"
  TAXO_URI = "http://purl.org/rss/1.0/modules/taxonomy/"

  RDF.install_ns(TAXO_PREFIX, TAXO_URI)

  TAXO_ELEMENTS = []

  %w(link).each do |name|
    full_name = "#{TAXO_PREFIX}_#{name}"
    BaseListener.install_get_text_element(TAXO_URI, name, "#{full_name}=")
    TAXO_ELEMENTS << "#{TAXO_PREFIX}_#{name}"
  end

  %w(topic topics).each do |name|
    class_name = Utils.to_class_name(name)
    BaseListener.install_class_name(TAXO_URI, name, "Taxonomy#{class_name}")
    TAXO_ELEMENTS << "#{TAXO_PREFIX}_#{name}"
  end

  module TaxonomyTopicsModel
    extend BaseModel
    
    def self.append_features(klass)
      super

      var_name = "#{TAXO_PREFIX}_topics"
      klass.install_have_child_element(var_name)
    end

    def taxo_validate(tags)
      found_topics = false
      tags.each do |tag|
        if tag == "topics"
          if found_topics
            raise TooMuchTagError.new(tag, tag_name)
          else
            found_topics = true
          end
        else
          raise UnknownTagError.new(tag, TAXO_URI)
        end
      end
    end

    class TaxonomyTopics < Element
      include RSS10
      
      Bag = ::RSS::RDF::Bag

      class << self
        def required_prefix
          TAXO_PREFIX
        end
        
        def required_uri
          TAXO_URI
        end
      end

      @tag_name = "topics"
      
      install_have_child_element("Bag")
        
      install_must_call_validator('rdf', ::RSS::RDF::URI)

      def initialize(bag=Bag.new)
        super()
        @Bag = bag
      end

      def full_name
        tag_name_with_prefix(TAXO_PREFIX)
      end

      def maker_target(target)
        target.taxo_topics
      end
      
      def to_s(need_convert=true, indent=calc_indent)
        rv = tag(indent) do |next_indent|
          [
           Bag_element(need_convert, next_indent),
           other_element(need_convert, next_indent),
          ]
        end
      end

      def resources
        if @Bag
          @Bag.lis.collect do |li|
            li.resource
          end
        else
          []
        end
      end

      private
      def children
        [@Bag]
      end

      def _tags
        rv = []
        rv << [::RSS::RDF::URI, 'Bag'] unless @Bag.nil?
        rv
      end
      
      def rdf_validate(tags)
        _validate(tags, [["Bag", nil]])
      end
    end
  end
  
  module TaxonomyTopicModel
    extend BaseModel
    
    def self.append_features(klass)
      super
      var_name = "#{TAXO_PREFIX}_topic"
      klass.install_have_children_element(var_name)
    end

    def taxo_validate(tags)
      tags.each do |tag|
        if tag != "topic"
          raise UnknownTagError.new(tag, TAXO_URI)
        end
      end
    end

    class TaxonomyTopic < Element
      include RSS10

      include DublinCoreModel
      include TaxonomyTopicsModel
      
      class << self
        def required_prefix
          TAXO_PREFIX
        end
        
        def required_uri
          TAXO_URI
        end
      end

      @tag_name = "topic"

      install_get_attribute("about", ::RSS::RDF::URI, true)
      install_text_element("#{TAXO_PREFIX}_link")
        
      def initialize(about=nil)
        super()
        @about = about
      end

      def full_name
        tag_name_with_prefix(TAXO_PREFIX)
      end
      
      def to_s(need_convert=true, indent=calc_indent)
        rv = tag(indent) do |next_indent|
          [
           other_element(need_convert, next_indent),
          ]
        end
      end

      def taxo_validate(tags)
        elements = %w(link topics)
        counter = {}
        
        tags.each do |tag|
          if elements.include?(tag)
            counter[tag] ||= 0
            counter[tag] += 1
            raise TooMuchTagError.new(tag, tag_name) if counter[tag] > 1
          else
            raise UnknownTagError.new(tag, TAXO_URI)
          end
        end
      end

      def maker_target(target)
        target.new_taxo_topic
      end
      
      private
      def children
        [@taxo_link, @taxo_topics]
      end

      def _attrs
        [
         ["#{RDF::PREFIX}:about", true, "about"]
        ]
      end
      
      def _tags
        rv = []
        rv << [TAXO_URI, "link"] unless @taxo_link.nil?
        rv << [TAXO_URI, "topics"] unless @taxo_topics.nil?
        rv
      end
    end
  end

  class RDF
    include TaxonomyTopicModel
    class Channel
      include TaxonomyTopicsModel
    end
    class Item; include TaxonomyTopicsModel; end
  end
end
