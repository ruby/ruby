require 'rss/dublincore'
require 'rss/maker/1.0'

module RSS
  module Maker
    module DublinCoreModel
      def self.append_features(klass)
        super

        ::RSS::DublinCoreModel::ELEMENTS.each do |element|
          klass.add_need_initialize_variable(element)
          klass.add_other_element(element)
          klass.__send__(:attr_accessor, element)
          klass.module_eval(<<-EOC, __FILE__, __LINE__)
            def setup_#{element}(rss, current)
              if #{element} and current.respond_to?(:#{element}=)
                current.#{element} = #{element}
              end
            end
EOC
        end
      end
    end

    class ChannelBase
      include DublinCoreModel

      undef_method(:dc_date)
      undef_method(:dc_date=)
      alias_method(:dc_date, :date)
      alias_method(:dc_date=, :date=)
    end
    
    class ImageBase; include DublinCoreModel; end
    class ItemsBase
      class ItemBase
        include DublinCoreModel
        
        undef_method(:dc_date)
        undef_method(:dc_date=)
        alias_method(:dc_date, :date)
        alias_method(:dc_date=, :date=)
      end
    end
    class TextinputBase; include DublinCoreModel; end
  end
end
