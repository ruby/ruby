require "rss/1.0"

require "rss/maker/base"

module RSS
  module Maker

    class RSS10 < RSSBase

      def initialize
        super("1.0")
      end

      private
      def make_rss
        RDF.new(@version, @encoding, @standalone)
      end

      def setup_elements(rss)
        setup_channel(rss)
        setup_image(rss)
        setup_items(rss)
        setup_textinput(rss)
      end

      class Channel < ChannelBase

        def to_rss(rss)
          set = false
          if @about
            channel = RDF::Channel.new(@about)
            set = setup_values(channel)
            if set
              channel.dc_dates.clear
              rss.channel = channel
              setup_items(rss)
              setup_image(rss)
              setup_textinput(rss)
              setup_other_elements(rss)
            end
          end

          if (!@about or !set) and variable_is_set?
            raise NotSetError.new("maker.channel", not_set_required_variables)
          end
        end

        def have_required_values?
          @about and @title and @link and @description
        end

        private
        def setup_items(rss)
          items = RDF::Channel::Items.new
          seq = items.Seq
          @maker.items.normalize.each do |item|
            seq.lis << RDF::Channel::Items::Seq::Li.new(item.link)
          end
          rss.channel.items = items
        end
        
        def setup_image(rss)
          if @maker.image.have_required_values?
            rss.channel.image = RDF::Channel::Image.new(@maker.image.url)
          end
        end

        def setup_textinput(rss)
          if @maker.textinput.have_required_values?
            textinput = RDF::Channel::Textinput.new(@maker.textinput.link)
            rss.channel.textinput = textinput
          end
        end

        def required_variable_names
          %w(about title link description)
        end
        
        class SkipDays < SkipDaysBase
          def to_rss(*args)
          end
          
          class Day < DayBase
          end
        end
        
        class SkipHours < SkipHoursBase
          def to_rss(*args)
          end

          class Hour < HourBase
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
          if @url
            image = RDF::Image.new(@url)
            set = setup_values(image)
            if set
              rss.image = image
              setup_other_elements(rss)
            end
          end
        end

        def have_required_values?
          @url and @title and link and @maker.channel.have_required_values?
        end

        private
        def variables
          super + ["link"]
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
            if @link
              item = RDF::Item.new(@link)
              set = setup_values(item)
              if set
                item.dc_dates.clear
                rss.items << item
                setup_other_elements(rss)
              end
            end
          end

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
          if @link
            textinput = RDF::Textinput.new(@link)
            set = setup_values(textinput)
            if set
              rss.textinput = textinput
              setup_other_elements(rss)
            end
          end
        end

        def have_required_values?
          @title and @description and @name and @link and
            @maker.channel.have_required_values?
        end
      end
    end

    add_maker(filename_to_version(__FILE__), RSS10)
  end
end
