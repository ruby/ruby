require 'rss/content'
require 'rss/maker/1.0'

module RSS
  module Maker
    module ContentModel
      def self.append_features(klass)
        super

        ::RSS::ContentModel::ELEMENTS.each do |element|
          klass.add_need_initialize_variable(element)
          klass.add_other_element(element)
          klass.__send__(:attr_accessor, element)
          klass.module_eval(<<-EOC, __FILE__, __LINE__)
            def setup_#{element}(rss, current)
              if #{element} and current.respond_to?(:#{element}=)
                current.#{element} = @#{element} if @#{element}
              end
            end
          EOC
        end
      end
    end

    class ItemsBase
      class ItemBase; include ContentModel; end
    end
  end
end
