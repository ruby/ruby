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
              current.#{element} = #{element} if #{element}
            end
EOC
        end
      end
    end

    class RSS10
      class Channel
        include DublinCoreModel

        alias_method(:_dc_date, :dc_date)
        alias_method(:_dc_date=, :dc_date=)
        alias_method(:dc_date, :date)
        alias_method(:dc_date=, :date=)
      end
      
      class Image; include DublinCoreModel; end
      class Items
        class Item
          include DublinCoreModel

          alias_method(:_dc_date, :dc_date)
          alias_method(:_dc_date=, :dc_date=)
          alias_method(:dc_date, :date)
          alias_method(:dc_date=, :date=)
        end
      end
      class Textinput; include DublinCoreModel; end
    end
  end
end
