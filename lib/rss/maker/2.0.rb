require "rss/2.0"

require "rss/maker/0.9"

module RSS
  module Maker
    
    class RSS20 < RSS09
      
      def initialize(rss_version="2.0")
        super
      end

      class Channel < RSS09::Channel

        add_other_element("cloud")
        
        def have_required_values?
          @title and @link and @description
        end

        private
        def setup_cloud(rss, current)
          @maker.channel.cloud.to_rss(rss)
        end

        class Cloud < RSS09::Channel::Cloud
          def to_rss(rss)
            cloud = Rss::Channel::Cloud.new
            set = setup_values(cloud)
            if set
              rss.channel.cloud = cloud
              setup_other_elements(rss)
            end
          end

          def have_required_values?
            @domain and @port and @path and
              @registerProcedure and @protocol
          end
        end
      end
      
      class Image < RSS09::Image
      end
      
      class Items < RSS09::Items
        
        class Item < RSS09::Items::Item

          alias_method(:pubDate, :date)
          
          def have_required_values?
            @title or @description
          end

          private
          def variables
            super + ["pubDate"]
          end

          class Guid < RSS09::Items::Item::Guid
            def to_rss(rss, item)
              guid = Rss::Channel::Item::Guid.new
              set = setup_values(guid)
              if set
                item.guid = guid
                setup_other_elements(rss)
              end
            end
            
            def have_required_values?
              @content
            end
          end

          class Enclosure < RSS09::Items::Item::Enclosure
            def to_rss(rss, item)
              enclosure = Rss::Channel::Item::Enclosure.new
              set = setup_values(enclosure)
              if set
                item.enclosure = enclosure
                setup_other_elements(rss)
              end
            end
            
            def have_required_values?
              @url and @length and @type
            end
          end

          class Source < RSS09::Items::Item::Source
            def to_rss(rss, item)
              source = Rss::Channel::Item::Source.new
              set = setup_values(source)
              if set
                item.source = source
                setup_other_elements(rss)
              end
            end
            
            def have_required_values?
              @url and @content
            end
          end

          class Category < RSS09::Items::Item::Category
            def to_rss(rss, item)
              category = Rss::Channel::Item::Category.new
              set = setup_values(category)
              if set
                item.category = category
                setup_other_elements(rss)
              end
            end
            
            def have_required_values?
              @content
            end
          end
        end
        
      end
      
      class Textinput < RSS09::Textinput
      end
    end
    
    add_maker(filename_to_version(__FILE__), RSS20)
  end
end
