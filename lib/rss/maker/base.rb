require 'forwardable'

require 'rss/rss'

module RSS
  module Maker

    module Base

      def self.append_features(klass)
        super

        klass.module_eval(<<-EOC, __FILE__, __LINE__)

        OTHER_ELEMENTS = []
        NEED_INITIALIZE_VARIABLES = []

        def self.inherited(subclass)
          subclass.const_set("OTHER_ELEMENTS", [])
          subclass.const_set("NEED_INITIALIZE_VARIABLES", [])

          subclass.module_eval(<<-EOEOC, __FILE__, __LINE__)
            def self.other_elements
              const_get("OTHER_ELEMENTS") + super
            end

            def self.need_initialize_variables
              const_get("NEED_INITIALIZE_VARIABLES") + super
            end
          EOEOC
        end

        def self.add_other_element(variable_name)
          const_get("OTHER_ELEMENTS") << variable_name
        end

        def self.other_elements
          OTHER_ELEMENTS
        end

        def self.add_need_initialize_variable(variable_name, init_value="nil")
          const_get("NEED_INITIALIZE_VARIABLES") << [variable_name, init_value]
        end

        def self.need_initialize_variables
          NEED_INITIALIZE_VARIABLES
        end

        def self.def_array_element(name)
          include Enumerable
          extend Forwardable

          def_delegators("@\#{name}", :<<, :[], :[]=, :first, :last)
          def_delegators("@\#{name}", :push, :pop, :shift, :unshift)
          def_delegators("@\#{name}", :each)
          
          add_need_initialize_variable(name, "[]")
        end
        EOC
      end
      
      def initialize(maker)
        @maker = maker
        initialize_variables
      end

      def have_required_values?
        true
      end
      
      private
      def initialize_variables
        self.class.need_initialize_variables.each do |variable_name, init_value|
          instance_eval("@#{variable_name} = #{init_value}", __FILE__, __LINE__)
        end
      end

      def setup_other_elements(rss)
        self.class.other_elements.each do |element|
          __send__("setup_#{element}", rss, current_element(rss))
        end
      end

      def setup_values(target)
        set = false
        if have_required_values?
          variables.each do |var|
            setter = "#{var}="
            if target.respond_to?(setter)
              value = self.__send__(var)
              if value
                target.__send__(setter, value)
                set = true
              end
            end
          end
        end
        set
      end

      def variables
        self.class.need_initialize_variables.find_all do |name, init|
          "nil" == init
        end.collect do |name, init|
          name
        end
      end

      def variable_is_set?
        variables.find {|var| !__send__(var).nil?}
      end

      def not_set_required_variables
        required_variable_names.find_all do |var|
          __send__(var).nil?
        end
      end

      def required_variables_are_set?
        required_variable_names.each do |var|
          return false if __send__(var).nil?
        end
        true
      end
      
    end

    class RSSBase
      include Base

      class << self
        def make(&block)
          new.make(&block)
        end
      end

      %w(xml_stylesheets channel image items textinput).each do |element|
        attr_reader element
        add_need_initialize_variable(element, "make_#{element}")
        module_eval(<<-EOC, __FILE__, __LINE__)
          private
          def setup_#{element}(rss)
            @#{element}.to_rss(rss)
          end

          def make_#{element}
            self.class::#{element[0,1].upcase}#{element[1..-1]}.new(self)
          end
EOC
      end
      
      attr_reader :rss_version
      attr_accessor :version, :encoding, :standalone
      
      def initialize(rss_version)
        super(self)
        @rss_version = rss_version
        @version = "1.0"
        @encoding = "UTF-8"
        @standalone = nil
      end
      
      def make
        if block_given?
          yield(self)
          to_rss
        else
          nil
        end
      end

      def to_rss
        rss = make_rss
        setup_xml_stylesheets(rss)
        setup_elements(rss)
        setup_other_elements(rss)
        if rss.channel
          rss
        else
          nil
        end
      end
      
      def current_element(rss)
        rss
      end
      
      private
      remove_method :make_xml_stylesheets
      def make_xml_stylesheets
        XMLStyleSheets.new(self)
      end
      
    end

    class XMLStyleSheets
      include Base

      def_array_element("xml_stylesheets")

      def to_rss(rss)
        @xml_stylesheets.each do |xss|
          xss.to_rss(rss)
        end
      end

      def new_xml_stylesheet
        xss = XMLStyleSheet.new(@maker)
        @xml_stylesheets << xss
        xss
      end

      class XMLStyleSheet
        include Base

        ::RSS::XMLStyleSheet::ATTRIBUTES.each do |attribute|
          attr_accessor attribute
          add_need_initialize_variable(attribute)
        end
        
        def to_rss(rss)
          xss = ::RSS::XMLStyleSheet.new
          guess_type_if_need(xss)
          set = setup_values(xss)
          if set
            rss.xml_stylesheets << xss
          end
        end

        def have_required_values?
          @href and @type
        end

        private
        def guess_type_if_need(xss)
          if @type.nil?
            xss.href = @href
            @type = xss.type
          end
        end
      end
    end
    
    class ChannelBase
      include Base

      %w(cloud categories skipDays skipHours).each do |element|
        attr_reader element
        add_other_element(element)
        add_need_initialize_variable(element, "make_#{element}")
        module_eval(<<-EOC, __FILE__, __LINE__)
          private
          def setup_#{element}(rss, current)
            @#{element}.to_rss(rss, current)
          end

          def make_#{element}
            self.class::#{element[0,1].upcase}#{element[1..-1]}.new(@maker)
          end
EOC
      end

      %w(about title link description language copyright
         managingEditor webMaster rating docs date
         lastBuildDate generator ttl).each do |element|
        attr_accessor element
        add_need_initialize_variable(element)
      end

      alias_method(:pubDate, :date)
      alias_method(:pubDate=, :date=)

      def current_element(rss)
        rss.channel
      end

      class SkipDaysBase
        include Base

        def_array_element("days")

        def new_day
          day = self.class::Day.new(@maker)
          @days << day 
          day
        end
        
        def current_element(rss)
          rss.channel.skipDays
        end

        class DayBase
          include Base
          
          %w(content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end

          def current_element(rss)
            rss.channel.skipDays.last
          end

        end
      end
      
      class SkipHoursBase
        include Base

        def_array_element("hours")

        def new_hour
          hour = self.class::Hour.new(@maker)
          @hours << hour 
          hour
        end
        
        def current_element(rss)
          rss.channel.skipHours
        end

        class HourBase
          include Base
          
          %w(content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end

          def current_element(rss)
            rss.channel.skipHours.last
          end

        end
      end
      
      class CloudBase
        include Base
        
        %w(domain port path registerProcedure protocol).each do |element|
          attr_accessor element
          add_need_initialize_variable(element)
        end
        
        def current_element(rss)
          rss.channel.cloud
        end

      end

      class CategoriesBase
        include Base
        
        def_array_element("categories")

        def new_category
          category = self.class::Category.new(@maker)
          @categories << category
          category
        end

        class CategoryBase
          include Base

          %w(domain content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end
      end
    end
    
    class ImageBase
      include Base

      %w(title url width height description).each do |element|
        attr_accessor element
        add_need_initialize_variable(element)
      end
      
      def link
        @maker.channel.link
      end

      def current_element(rss)
        rss.image
      end
    end
    
    class ItemsBase
      include Base

      def_array_element("items")
      
      attr_accessor :do_sort, :max_size
      
      def initialize(maker)
        super
        @do_sort = false
        @max_size = -1
      end
      
      def normalize
        sort_if_need[0..@max_size]
      end
      
      def current_element(rss)
        rss.items
      end

      def new_item
        item = self.class::Item.new(@maker)
        @items << item 
        item
      end
      
      private
      def sort_if_need
        if @do_sort.respond_to?(:call)
          @items.sort do |x, y|
            @do_sort.call(x, y)
          end
        elsif @do_sort
          @items.sort do |x, y|
            y <=> x
          end
        else
          @items
        end
      end

      class ItemBase
        include Base
        
        %w(guid enclosure source categories).each do |element|
          attr_reader element
          add_other_element(element)
          add_need_initialize_variable(element, "make_#{element}")
          module_eval(<<-EOC, __FILE__, __LINE__)
          private
          def setup_#{element}(rss, current)
            @#{element}.to_rss(rss, current)
          end

          def make_#{element}
            self.class::#{element[0,1].upcase}#{element[1..-1]}.new(@maker)
          end
EOC
        end
      
        %w(title link description date author comments).each do |element|
          attr_accessor element
          add_need_initialize_variable(element)
        end

        alias_method(:pubDate, :date)
        alias_method(:pubDate=, :date=)

        def <=>(other)
          if @date and other.date
            @date <=> other.date
          elsif @date
            1
          elsif other.date
            -1
          else
            0
          end
        end
      
        def current_element(rss)
          rss.items.last
        end

        class GuidBase
          include Base

          %w(isPermaLink content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end
      
        class EnclosureBase
          include Base

          %w(url length type).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end
      
        class SourceBase
          include Base

          %w(url content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end
      
        CategoriesBase = ChannelBase::CategoriesBase
      
      end
    end

    class TextinputBase
      include Base

      %w(title description name link).each do |element|
        attr_accessor element
        add_need_initialize_variable(element)
      end
      
      def current_element(rss)
        rss.textinput
      end

    end
    
  end
end
