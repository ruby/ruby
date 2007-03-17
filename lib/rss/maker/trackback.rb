require 'rss/trackback'
require 'rss/maker/1.0'
require 'rss/maker/2.0'

module RSS
  module Maker
    module TrackBackModel
      def self.append_features(klass)
        super

        name = "#{RSS::TRACKBACK_PREFIX}_ping"
        klass.add_need_initialize_variable(name)
        klass.add_other_element(name)
        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          attr_accessor :#{name}
          def setup_#{name}(feed, current)
            if #{name} and current.respond_to?(:#{name}=)
              current.#{name} = #{name}
            end
          end
        EOC

        name = "#{RSS::TRACKBACK_PREFIX}_abouts"
        klass.add_need_initialize_variable(name, "make_#{name}")
        klass.add_other_element(name)
        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          attr_accessor :#{name}
          def make_#{name}
            self.class::TrackBackAbouts.new(self)
          end

          def setup_#{name}(feed, current)
            @#{name}.to_feed(feed, current)
          end
        EOC
      end

      class TrackBackAboutsBase
        include Base

        def_array_element("about", nil, "self.class::TrackBackAbout")

        class TrackBackAboutBase
          include Base

          attr_accessor :value
          add_need_initialize_variable("value")
          
          alias_method(:resource, :value)
          alias_method(:resource=, :value=)
          alias_method(:content, :value)
          alias_method(:content=, :value=)

          def have_required_values?
            @value
          end

          def to_feed(feed, current)
            if current.respond_to?(:trackback_abouts) and have_required_values?
              about = current.class::TrackBackAbout.new
              setup_values(about)
              setup_other_elements(about)
              current.trackback_abouts << about
            end
          end
        end
      end
    end

    class ItemsBase
      class ItemBase; include TrackBackModel; end
    end

    makers.each do |maker|
      maker.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
        class Items
          class Item
            class TrackBackAbouts < TrackBackAboutsBase
              class TrackBackAbout < TrackBackAboutBase
              end
            end
          end
        end
      EOC
    end
  end
end
