require 'rss/syndication'
require 'rss/maker/1.0'

module RSS
  module Maker
    module SyndicationModel
      def self.append_features(klass)
        super

        ::RSS::SyndicationModel::ELEMENTS.each do |element|
          klass.add_need_initialize_variable(element)
          klass.add_other_element(element)
          klass.__send__(:attr_accessor, element)
          klass.module_eval(<<-EOC, __FILE__, __LINE__)
            def setup_#{element}(rss, current)
              current.#{element} = @#{element} if @#{element}
            end
EOC
        end
      end
    end

    class RSS10
      class Channel; include SyndicationModel; end
    end
  end
end
