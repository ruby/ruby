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
            
            def setup_#{full_plural_name}(rss, current)
              @#{full_plural_name}.to_rss(rss, current)
            end

            def #{full_name}
              @#{full_plural_name}[0] and @#{full_plural_name}[0].value
            end
            
            def #{full_name}=(new_value)
              @#{full_plural_name}[0] = #{full_klass_name}.new(self)
              @#{full_plural_name}[0].value = new_value
            end
EOC
        end
      end

      ::RSS::DublinCoreModel::ELEMENT_NAME_INFOS.each do |name, plural_name|
        plural_name ||= "#{name}s"
        klass_name = Utils.to_class_name(name)
        plural_klass_name = "DublinCore#{Utils.to_class_name(plural_name)}"
        module_eval(<<-EOC, __FILE__, __LINE__)
        class #{plural_klass_name}Base
          include Base

          def_array_element(#{plural_name.dump})
                            
          def new_#{name}
            #{name} = self.class::#{klass_name}.new(self)
            @#{plural_name} << #{name}
            #{name}
          end

          def to_rss(rss, current)
            @#{plural_name}.each do |#{name}|
              #{name}.to_rss(rss, current)
            end
          end
        
          class #{klass_name}Base
            include Base

            attr_accessor :value
            add_need_initialize_variable("value")
            alias_method(:content, :value)
            alias_method(:content=, :value=)

            def have_required_values?
              @value
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
          full_klass_name = "DublinCore#{klass_name}"
          klass.module_eval(<<-EOC, *Utils.get_file_and_line_from_caller(1))
          class #{plural_klass_name} < #{plural_klass_name}Base
            class #{klass_name} < #{klass_name}Base
              def to_rss(rss, current)
                if value and current.respond_to?(:dc_#{name})
                  new_item = current.class::#{full_klass_name}.new(value)
                  current.dc_#{plural_name} << new_item
                end
              end
            end
          end
EOC
        end
      end
    end

    class ChannelBase
      include DublinCoreModel
      
      remove_method(:date)
      remove_method(:date=)
      alias_method(:date, :dc_date)
      alias_method(:date=, :dc_date=)
    end
    
    class ImageBase; include DublinCoreModel; end
    class ItemsBase
      class ItemBase
        include DublinCoreModel
        
        remove_method(:date)
        remove_method(:date=)
        alias_method(:date, :dc_date)
        alias_method(:date=, :dc_date=)
      end
    end
    class TextinputBase; include DublinCoreModel; end

    class RSS10
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
    end
    
    class RSS09
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
    end
  end
end
