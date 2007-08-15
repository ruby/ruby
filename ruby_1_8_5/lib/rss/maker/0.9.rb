require "rss/0.9"

require "rss/maker/base"

module RSS
  module Maker
    
    class RSS09 < RSSBase
      
      def initialize(rss_version="0.91")
        super
      end
      
      private
      def make_rss
        Rss.new(@rss_version, @version, @encoding, @standalone)
      end

      def setup_elements(rss)
        setup_channel(rss)
      end

      class Channel < ChannelBase
        
        def to_rss(rss)
          channel = Rss::Channel.new
          set = setup_values(channel)
          if set
            rss.channel = channel
            setup_items(rss)
            setup_image(rss)
            setup_textinput(rss)
            setup_other_elements(rss)
            if rss.channel.image
              rss
            else
              nil
            end
          elsif variable_is_set?
            raise NotSetError.new("maker.channel", not_set_required_variables)
          end
        end
        
        def have_required_values?
          @title and @link and @description and @language
        end
        
        private
        def setup_items(rss)
          @maker.items.to_rss(rss)
        end
        
        def setup_image(rss)
          @maker.image.to_rss(rss)
        end
        
        def setup_textinput(rss)
          @maker.textinput.to_rss(rss)
        end
        
        def variables
          super + ["pubDate"]
        end

        def required_variable_names
          %w(title link description language)
        end
        
        class SkipDays < SkipDaysBase
          def to_rss(rss, channel)
            unless @days.empty?
              skipDays = Rss::Channel::SkipDays.new
              channel.skipDays = skipDays
              @days.each do |day|
                day.to_rss(rss, skipDays.days)
              end
            end
          end
          
          class Day < DayBase
            def to_rss(rss, days)
              day = Rss::Channel::SkipDays::Day.new
              set = setup_values(day)
              if set
                days << day
                setup_other_elements(rss)
              end
            end

            def have_required_values?
              @content
            end
          end
        end
        
        class SkipHours < SkipHoursBase
          def to_rss(rss, channel)
            unless @hours.empty?
              skipHours = Rss::Channel::SkipHours.new
              channel.skipHours = skipHours
              @hours.each do |hour|
                hour.to_rss(rss, skipHours.hours)
              end
            end
          end
          
          class Hour < HourBase
            def to_rss(rss, hours)
              hour = Rss::Channel::SkipHours::Hour.new
              set = setup_values(hour)
              if set
                hours << hour
                setup_other_elements(rss)
              end
            end

            def have_required_values?
              @content
            end
          end
        end
        
        class Cloud < CloudBase
          def to_rss(*args)
          end
        end

        class Categories < CategoriesBase
          def to_rss(*args)
          end

          class Category < CategoryBase
          end
        end
      end
      
      class Image < ImageBase
        def to_rss(rss)
          image = Rss::Channel::Image.new
          set = setup_values(image)
          if set
            image.link = link
            rss.channel.image = image
            setup_other_elements(rss)
          end
        end
        
        def have_required_values?
          @url and @title and link
        end
      end
      
      class Items < ItemsBase
        def to_rss(rss)
          if rss.channel
            normalize.each do |item|
              item.to_rss(rss)
            end
            setup_other_elements(rss)
          end
        end
        
        class Item < ItemBase
          def to_rss(rss)
            item = Rss::Channel::Item.new
            set = setup_values(item)
            if set
              rss.items << item
              setup_other_elements(rss)
            end
          end
          
          private
          def have_required_values?
            @title and @link
          end

          class Guid < GuidBase
            def to_rss(*args)
            end
          end
        
          class Enclosure < EnclosureBase
            def to_rss(*args)
            end
          end
        
          class Source < SourceBase
            def to_rss(*args)
            end
          end
        
          class Categories < CategoriesBase
            def to_rss(*args)
            end

            class Category < CategoryBase
            end
          end
          
        end
      end
      
      class Textinput < TextinputBase
        def to_rss(rss)
          textInput = Rss::Channel::TextInput.new
          set = setup_values(textInput)
          if set
            rss.channel.textInput = textInput
            setup_other_elements(rss)
          end
        end

        private
        def have_required_values?
          @title and @description and @name and @link
        end
      end
    end
    
    add_maker(filename_to_version(__FILE__), RSS09)
    add_maker(filename_to_version(__FILE__) + "1", RSS09)
  end
end
