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

      klass.install_must_call_validator(TAXO_PREFIX, TAXO_URI)
      %w(topics).each do |name|
        klass.install_have_child_element("#{TAXO_PREFIX}_#{name}")
        klass.install_model(name, TAXO_URI, "?")
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
      install_model("Bag", RDF::URI, nil)
      install_must_call_validator('rdf', RDF::URI)

      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.Bag = args[0]
        end
        self.Bag ||= Bag.new
      end

      def full_name
        tag_name_with_prefix(TAXO_PREFIX)
      end

      def maker_target(target)
        target.taxo_topics
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
        rv << [RDF::URI, 'Bag'] unless @Bag.nil?
        rv
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

      install_get_attribute("about", ::RSS::RDF::URI, true, nil, nil,
                            "#{RDF::PREFIX}:about")
      install_text_element("#{TAXO_PREFIX}_link")
        
      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.about = args[0]
        end
      end

      def full_name
        tag_name_with_prefix(TAXO_PREFIX)
      end

      def maker_target(target)
        target.new_taxo_topic
      end
      
      private
      def children
        [@taxo_link, @taxo_topics]
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
