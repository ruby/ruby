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
          subclass.const_set("OTHER_ELEMENTS",
                             OTHER_ELEMENTS.dup)
          subclass.const_set("NEED_INITIALIZE_VARIABLES",
                             NEED_INITIALIZE_VARIABLES.dup)
        end

        def self.add_other_element(variable_name)
          const_get("OTHER_ELEMENTS") << variable_name
        end
        
        def self.other_elements
          const_get("OTHER_ELEMENTS")
        end

        def self.add_need_initialize_variable(variable_name)
          const_get("NEED_INITIALIZE_VARIABLES") << variable_name
        end
        
        def self.need_initialize_variables
          const_get("NEED_INITIALIZE_VARIABLES")
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
        self.class.need_initialize_variables.each do |variable_name|
          instance_eval("@#{variable_name} = nil", __FILE__, __LINE__)
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
        self.class.need_initialize_variables
      end
      
    end
    
    class RSSBase
      include Base
      
      class << self
        def make(&block)
          new.make(&block)
        end
      end

      attr_reader :rss_version, :xml_stylesheets
      attr_reader :channel, :image, :items, :textinput
      
      attr_accessor :version, :encoding, :standalone
      
      def initialize(rss_version)
        super(self)
        @rss_version = rss_version
        @version = "1.0"
        @encoding = "UTF-8"
        @standalone = nil
        @xml_stylesheets = make_xml_stylesheets
        @channel = make_channel
        @image = make_image
        @items = make_items
        @textinput = make_textinput
      end
      
      def make(&block)
        block.call(self) if block
        to_rss
      end

      def current_element(rss)
        rss
      end
      
      private
      def make_xml_stylesheets
        XMLStyleSheets.new(self)
      end
      
      def make_channel
        self.class::Channel.new(self)
      end
      
      def make_image
        self.class::Image.new(self)
      end
      
      def make_items
        self.class::Items.new(self)
      end
      
      def make_textinput
        self.class::Textinput.new(self)
      end

      def setup_xml_stylesheets(rss)
        @xml_stylesheets.to_rss(rss)
      end
      
    end

    class XMLStyleSheets
      include Base

      extend Forwardable

      def_delegators(:@xml_stylesheets, :<<, :[], :[]=, :first, :last)
      def_delegators(:@xml_stylesheets, :push, :pop, :shift, :unshift)

      def initialize(maker)
        super
        @xml_stylesheets = []
      end

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
          set = setup_values(xss)
          if set
            rss.xml_stylesheets << xss
          end
        end
      end
    end
    
    class ChannelBase
      include Base

      attr_reader :cloud

      %w(about title link description language copyright
      managingEditor webMaster rating docs skipDays
      skipHours date lastBuildDate category generator ttl
      ).each do |element|
        attr_accessor element
        add_need_initialize_variable(element)
      end

      def initialize(maker)
        super
        @cloud = make_cloud
      end

      def current_element(rss)
        rss.channel
      end

      private
      def make_cloud
        self.class::Cloud.new(@maker)
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

      extend Forwardable

      def_delegators(:@items, :<<, :[], :[]=, :first, :last)
      def_delegators(:@items, :push, :pop, :shift, :unshift)
      
      attr_accessor :sort
      
      def initialize(maker)
        super
        @items = []
        @sort = false
      end
      
      def normalize
        sort_if_need
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
        if @sort.respond_to?(:call)
          @items.sort do |x, y|
            @sort.call(x, y)
          end
        elsif @sort
          @items.sort do |x, y|
            y <=> x
          end
        else
          @items
        end
      end

      class ItemBase
        include Base
        
        %w(guid enclosure source category).each do |element|
          attr_reader element
          add_other_element(element)
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

        def initialize(maker)
          super
          @guid = make_guid
          @enclosure = make_enclosure
          @source = make_source
          @category = make_category
        end
      
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
      
        class CategoryBase
          include Base

          %w(domain content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end
      
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
