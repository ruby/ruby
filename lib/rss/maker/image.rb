require 'rss/image'
require 'rss/maker/1.0'
require 'rss/maker/dublincore'

module RSS
  module Maker
    module ImageItemModel
      def self.append_features(klass)
        super

        name = "#{RSS::IMAGE_PREFIX}_item"
        klass.add_need_initialize_variable(name, "make_#{name}")
        klass.add_other_element(name)
        klass.__send__(:attr_reader, name)
        klass.module_eval(<<-EOC, __FILE__, __LINE__)
          def setup_#{name}(rss, current)
            if @#{name}
              @#{name}.to_rss(rss, current)
            end
          end

          def make_#{name}
            self.class::#{Utils.to_class_name(name)}.new(@maker)
          end
EOC
      end

      class ImageItemBase
        include Base
        include Maker::DublinCoreModel

        attr_accessor :about, :resource, :image_width, :image_height
        add_need_initialize_variable(:about, :resource)
        add_need_initialize_variable(:image_width, :image_height)
        alias width= image_width=
        alias width image_width
        alias height= image_height=
        alias height image_height

        def have_required_values?
          @about
        end
      end
    end

    module ImageFaviconModel
      def self.append_features(klass)
        super

        name = "#{RSS::IMAGE_PREFIX}_favicon"
        klass.add_need_initialize_variable(name, "make_#{name}")
        klass.add_other_element(name)
        klass.__send__(:attr_reader, name)
        klass.module_eval(<<-EOC, __FILE__, __LINE__)
          def setup_#{name}(rss, current)
            if @#{name}
              @#{name}.to_rss(rss, current)
            end
          end

          def make_#{name}
            self.class::#{Utils.to_class_name(name)}.new(@maker)
          end
EOC
      end

      class ImageFaviconBase
        include Base
        include Maker::DublinCoreModel

        attr_accessor :about, :image_size
        add_need_initialize_variable(:about, :image_size)
        alias size image_size
        alias size= image_size=

        def have_required_values?
          @about and @image_size
        end
      end
    end

    class ChannelBase; include Maker::ImageFaviconModel; end
    
    class ItemsBase
      class ItemBase; include Maker::ImageItemModel; end
    end

    class RSS10
      class Items
        class Item
          class ImageItem < ImageItemBase
            def to_rss(rss, current)
              if @about
                item = ::RSS::ImageItemModel::Item.new(@about, @resource)
                setup_values(item)
                current.image_item = item
              end
            end
          end
        end
      end
      
      class Channel
        class ImageFavicon < ImageFaviconBase
          def to_rss(rss, current)
            if @about and @image_size
              args = [@about, @image_size]
              favicon = ::RSS::ImageFaviconModel::Favicon.new(*args)
              setup_values(favicon)
              current.image_favicon = favicon
            end
          end
        end
      end
    end

    class RSS09
      class Items
        class Item
          class ImageItem < ImageItemBase
            def to_rss(*args)
            end
          end
        end
      end
      
      class Channel
        class ImageFavicon < ImageFaviconBase
          def to_rss(*args)
          end
        end
      end
    end

  end
end
