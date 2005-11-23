require 'rss/taxonomy'
require 'rss/maker/1.0'
require 'rss/maker/dublincore'

module RSS
  module Maker
    module TaxoTopicsModel
      def self.append_features(klass)
        super

        klass.add_need_initialize_variable("taxo_topics", "make_taxo_topics")
        klass.add_other_element("taxo_topics")
        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          attr_reader :taxo_topics
          def make_taxo_topics
            self.class::TaxoTopics.new(@maker)
          end
            
          def setup_taxo_topics(rss, current)
            @taxo_topics.to_rss(rss, current)
          end
EOC
      end

      def self.install_taxo_topics(klass)
        klass.module_eval(<<-EOC, *Utils.get_file_and_line_from_caller(1))
          class TaxoTopics < TaxoTopicsBase
            def to_rss(rss, current)
              if current.respond_to?(:taxo_topics)
                topics = current.class::TaxoTopics.new
                bag = topics.Bag
                @resources.each do |resource|
                  bag.lis << RDF::Bag::Li.new(resource)
                end
                current.taxo_topics = topics
              end
            end
          end
EOC
      end

      class TaxoTopicsBase
        include Base

        attr_reader :resources
        def_array_element("resources")
      end
    end

    module TaxoTopicModel
      def self.append_features(klass)
        super

        klass.add_need_initialize_variable("taxo_topics", "make_taxo_topics")
        klass.add_other_element("taxo_topics")
        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          attr_reader :taxo_topics
          def make_taxo_topics
            self.class::TaxoTopics.new(@maker)
          end
            
          def setup_taxo_topics(rss, current)
            @taxo_topics.to_rss(rss, current)
          end

          def taxo_topic
            @taxo_topics[0] and @taxo_topics[0].value
          end
            
          def taxo_topic=(new_value)
            @taxo_topic[0] = self.class::TaxoTopic.new(self)
            @taxo_topic[0].value = new_value
          end
EOC
      end
    
      def self.install_taxo_topic(klass)
        klass.module_eval(<<-EOC, *Utils.get_file_and_line_from_caller(1))
          class TaxoTopics < TaxoTopicsBase
            class TaxoTopic < TaxoTopicBase
              DublinCoreModel.install_dublin_core(self)
              TaxoTopicsModel.install_taxo_topics(self)

              def to_rss(rss, current)
                if current.respond_to?(:taxo_topics)
                  topic = current.class::TaxoTopic.new(value)
                  topic.taxo_link = value
                  taxo_topics.to_rss(rss, topic) if taxo_topics
                  current.taxo_topics << topic
                  setup_other_elements(rss)
                end
              end

              def current_element(rss)
                super.taxo_topics.last
              end
            end
          end
EOC
      end

      class TaxoTopicsBase
        include Base
        
        def_array_element("taxo_topics")
                            
        def new_taxo_topic
          taxo_topic = self.class::TaxoTopic.new(self)
          @taxo_topics << taxo_topic
          taxo_topic
        end

        def to_rss(rss, current)
          @taxo_topics.each do |taxo_topic|
            taxo_topic.to_rss(rss, current)
          end
        end
        
        class TaxoTopicBase
          include Base
          include DublinCoreModel
          include TaxoTopicsModel
          
          attr_accessor :value
          add_need_initialize_variable("value")
          alias_method(:taxo_link, :value)
          alias_method(:taxo_link=, :value=)
          
          def have_required_values?
            @value
          end
        end
      end
    end

    class RSSBase
      include TaxoTopicModel
    end
    
    class ChannelBase
      include TaxoTopicsModel
    end
    
    class ItemsBase
      class ItemBase
        include TaxoTopicsModel
      end
    end

    class RSS10
      TaxoTopicModel.install_taxo_topic(self)
      
      class Channel
        TaxoTopicsModel.install_taxo_topics(self)
      end

      class Items
        class Item
          TaxoTopicsModel.install_taxo_topics(self)
        end
      end
    end
    
    class RSS09
      TaxoTopicModel.install_taxo_topic(self)
      
      class Channel
        TaxoTopicsModel.install_taxo_topics(self)
      end

      class Items
        class Item
          TaxoTopicsModel.install_taxo_topics(self)
        end
      end
    end
  end
end
