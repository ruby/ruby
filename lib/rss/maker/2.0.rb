require "rss/2.0"

require "rss/maker/0.9"

module RSS
  module Maker
    
    class RSS20 < RSS09
      
      def initialize(rss_version="2.0")
        super
      end

      class Channel < RSS09::Channel

        def have_required_values?
          @title and @link and @description
        end

        def required_variable_names
          %w(title link description)
        end
        
        class SkipDays < RSS09::Channel::SkipDays
          class Day < RSS09::Channel::SkipDays::Day
          end
        end
        
        class SkipHours < RSS09::Channel::SkipHours
          class Hour < RSS09::Channel::SkipHours::Hour
          end
        end
        
        class Cloud < RSS09::Channel::Cloud
          def to_rss(rss, channel)
            cloud = Rss::Channel::Cloud.new
            set = setup_values(cloud)
            if set
              channel.cloud = cloud
              setup_other_elements(rss)
            end
          end

          def have_required_values?
            @domain and @port and @path and
              @registerProcedure and @protocol
          end
        end

        class Categories < RSS09::Channel::Categories
          def to_rss(rss, channel)
            @categories.each do |category|
              category.to_rss(rss, channel)
            end
          end
          
          class Category < RSS09::Channel::Categories::Category
            def to_rss(rss, channel)
              category = Rss::Channel::Category.new
              set = setup_values(category)
              if set
                channel.categories << category
                setup_other_elements(rss)
              end
            end
            
            def have_required_values?
              @content
            end
          end
        end
        
      end
      
      class Image < RSS09::Image
      end
      
      class Items < RSS09::Items
        
        class Item < RSS09::Items::Item

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

          class Categories < RSS09::Items::Item::Categories
            def to_rss(rss, item)
              @categories.each do |category|
                category.to_rss(rss, item)
              end
            end
          
            class Category < RSS09::Items::Item::Categories::Category
              def to_rss(rss, item)
                category = Rss::Channel::Item::Category.new
                set = setup_values(category)
                if set
                  item.categories << category
                  setup_other_elements(rss)
                end
              end
              
              def have_required_values?
                @content
              end
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
