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
        klass.module_eval(<<-EOC, __FILE__, __LINE__+1)
          attr_accessor :#{name}
          def setup_#{name}(rss, current)
            if #{name} and current.respond_to?(:#{name}=)
              current.#{name} = #{name}
            end
          end
        EOC

        name = "#{RSS::TRACKBACK_PREFIX}_abouts"
        klass.add_need_initialize_variable(name, "make_#{name}")
        klass.add_other_element(name)
        klass.module_eval(<<-EOC, __FILE__, __LINE__+1)
          attr_accessor :#{name}
          def make_#{name}
            self.class::TrackBackAbouts.new(self)
          end

          def setup_#{name}(rss, current)
            @#{name}.to_rss(rss, current)
          end
        EOC
      end

      class TrackBackAboutsBase
        include Base

        def_array_element("abouts")
        
        def new_about
          about = self.class::About.new(@maker)
          @abouts << about 
          about
        end

        def to_rss(rss, current)
          @abouts.each do |about|
            about.to_rss(rss, current)
          end
        end
        
        class AboutBase
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
          
        end
      end
    end

    class ItemsBase
      class ItemBase; include TrackBackModel; end
    end

    class RSS10
      class Items
        class Item
          class TrackBackAbouts < TrackBackAboutsBase
            class About < AboutBase
              def to_rss(rss, current)
                if resource
                  about = ::RSS::TrackBackModel10::About.new(resource)
                  current.trackback_abouts << about
                end
              end
            end
          end
        end
      end
    end

    class RSS09
      class Items
        class Item
          class TrackBackAbouts < TrackBackAboutsBase
            def to_rss(*args)
            end
            class About < AboutBase
            end
          end
        end
      end
    end
    
    class RSS20
      class Items
        class Item
          class TrackBackAbouts < TrackBackAboutsBase
            class About < AboutBase
              def to_rss(rss, current)
                if content
                  about = ::RSS::TrackBackModel20::About.new(content)
                  current.trackback_abouts << about
                end
              end
            end
          end
        end
      end
    end
    
  end
end
