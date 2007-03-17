require 'rss/dublincore'
require 'rss/maker/1.0'

module RSS
  module Maker
    module DublinCoreModel
      def self.append_features(klass)
        super

        ::RSS::DublinCoreModel::ELEMENT_NAME_INFOS.each do |name, plural_name|
          plural_name ||= "#{name}s"
          full_name = "#{RSS::DC_PREFIX}_#{name}"
          full_plural_name = "#{RSS::DC_PREFIX}_#{plural_name}"
          klass_name = Utils.to_class_name(name)
          plural_klass_name = "DublinCore#{Utils.to_class_name(plural_name)}"
          full_plural_klass_name = "self.class::#{plural_klass_name}"
          full_klass_name = "#{full_plural_klass_name}::#{klass_name}"
          klass.add_need_initialize_variable(full_plural_name,
                                             "make_#{full_plural_name}")
          klass.add_other_element(full_plural_name)
          klass.module_eval(<<-EOC, __FILE__, __LINE__+1)
            attr_accessor :#{full_plural_name}
            def make_#{full_plural_name}
              #{full_plural_klass_name}.new(@maker)
            end
            
            def setup_#{full_plural_name}(feed, current)
              @#{full_plural_name}.to_feed(feed, current)
            end

            def #{full_name}
              @#{full_plural_name}[0] and @#{full_plural_name}[0].value
            end
            
            def #{full_name}=(new_value)
              @#{full_plural_name}[0] = #{full_klass_name}.new(self)
              @#{full_plural_name}[0].value = new_value
            end

            def new_#{full_name}(value=nil)
              #{full_name} = #{full_klass_name}.new(self)
              #{full_name}.value = value
              @#{full_plural_name} << #{full_name}
              if block_given?
                yield #{full_name}
              else
                #{full_name}
              end
            end
EOC
        end

        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          # For backward compatibility
          alias #{DC_PREFIX}_rightses #{DC_PREFIX}_rights_list
EOC
      end

      ::RSS::DublinCoreModel::ELEMENT_NAME_INFOS.each do |name, plural_name|
        plural_name ||= "#{name}s"
        klass_name = Utils.to_class_name(name)
        full_klass_name = "DublinCore#{klass_name}"
        plural_klass_name = "DublinCore#{Utils.to_class_name(plural_name)}"
        module_eval(<<-EOC, __FILE__, __LINE__)
        class #{plural_klass_name}Base
          include Base

          def_array_element(#{name.dump}, #{plural_name.dump})

          class #{klass_name}Base
            include Base

            attr_accessor :value
            add_need_initialize_variable("value")
            alias_method(:content, :value)
            alias_method(:content=, :value=)

            def have_required_values?
              @value
            end

            def to_feed(feed, current)
              if value and current.respond_to?(:dc_#{name})
                new_item = current.class::#{full_klass_name}.new(value)
                current.dc_#{plural_name} << new_item
              end
            end
          end
        end
        EOC
      end

      def self.install_dublin_core(klass)
        ::RSS::DublinCoreModel::ELEMENT_NAME_INFOS.each do |name, plural_name|
          plural_name ||= "#{name}s"
          klass_name = Utils.to_class_name(name)
          plural_klass_name = "DublinCore#{Utils.to_class_name(plural_name)}"
          klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          class #{plural_klass_name} < #{plural_klass_name}Base
            class #{klass_name} < #{klass_name}Base
            end
          end
EOC
        end
      end
    end

    class ChannelBase
      include DublinCoreModel
    end
    
    class ImageBase; include DublinCoreModel; end
    class ItemsBase
      class ItemBase
        include DublinCoreModel
      end
    end
    class TextinputBase; include DublinCoreModel; end

    makers.each do |maker|
      maker.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
        class Channel
          DublinCoreModel.install_dublin_core(self)
        end

        class Image
          DublinCoreModel.install_dublin_core(self)
        end

        class Items
          class Item
            DublinCoreModel.install_dublin_core(self)
          end
        end

        class Textinput
          DublinCoreModel.install_dublin_core(self)
        end
      EOC
    end
  end
end
