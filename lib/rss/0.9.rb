require "rss/parser"

module RSS

  module RSS09
    NSPOOL = {}
    ELEMENTS = []

    def self.append_features(klass)
      super
      
      klass.install_must_call_validator('', nil)
    end
  end

  class Rss < Element

    include RSS09
    include RootElementMixin
    include XMLStyleSheetMixin

    [
      ["channel", nil],
    ].each do |tag, occurs|
      install_model(tag, occurs)
    end

    %w(channel).each do |x|
      install_have_child_element(x)
    end

    attr_accessor :rss_version, :version, :encoding, :standalone
    
    def initialize(rss_version, version=nil, encoding=nil, standalone=nil)
      super
    end

    def items
      if @channel
        @channel.items
      else
        []
      end
    end

    def image
      if @channel
        @channel.image
      else
        nil
      end
    end

    def textinput
      if @channel
        @channel.textInput
      else
        nil
      end
    end
    
    def to_s(convert=true, indent=calc_indent)
      rv = tag(indent, ns_declarations) do |next_indent|
        [
          channel_element(false, next_indent),
          other_element(false, next_indent),
        ]
      end
      rv = @converter.convert(rv) if convert and @converter
      rv
    end

    private
    def children
      [@channel]
    end

    def _tags
      [
        [nil, 'channel'],
      ].delete_if {|x| send(x[1]).nil?}
    end

    def _attrs
      [
        ["version", true, "rss_version"],
      ]
    end

    class Channel < Element

      include RSS09

      [
        ["title", nil],
        ["link", nil],
        ["description", nil],
        ["language", nil],
        ["copyright", "?"],
        ["managingEditor", "?"],
        ["webMaster", "?"],
        ["rating", "?"],
        ["docs", "?"],
      ].each do |x, occurs|
        install_text_element(x)
        install_model(x, occurs)
      end

      [
        ["pubDate", "?"],
        ["lastBuildDate", "?"],
      ].each do |x, occurs|
        install_date_element(x, 'rfc822')
        install_model(x, occurs)
      end

      [
        ["skipDays", "?"],
        ["skipHours", "?"],
        ["image", nil],
        ["textInput", "?"],
      ].each do |x, occurs|
        install_have_child_element(x)
        install_model(x, occurs)
      end
      
      [
        ["cloud", "?"]
      ].each do |x, occurs|
        install_have_attribute_element(x)
        install_model(x, occurs)
      end
      
      [
        ["item", "*"]
      ].each do |x, occurs|
        install_have_children_element(x)
        install_model(x, occurs)
      end

      def initialize()
        super()
      end

      def to_s(convert=true, indent=calc_indent)
        rv = tag(indent) do |next_indent|
          [
            title_element(false, next_indent),
            link_element(false, next_indent),
            description_element(false, next_indent),
            language_element(false, next_indent),
            copyright_element(false, next_indent),
            managingEditor_element(false, next_indent),
            webMaster_element(false, next_indent),
            rating_element(false, next_indent),
            pubDate_element(false, next_indent),
            lastBuildDate_element(false, next_indent),
            docs_element(false, next_indent),
            cloud_element(false, next_indent),
            skipDays_element(false, next_indent),
            skipHours_element(false, next_indent),
            image_element(false, next_indent),
            item_elements(false, next_indent),
            textInput_element(false, next_indent),
            other_element(false, next_indent),
          ]
        end
        rv = @converter.convert(rv) if convert and @converter
        rv
      end

      private
      def children
        [@skipDays, @skipHours, @image, @textInput, @cloud, *@item]
      end

      def _tags
        rv = [
          "title",
          "link",
          "description",
          "language",
          "copyright",
          "managingEditor",
          "webMaster",
          "rating",
          "docs",
          "skipDays",
          "skipHours",
          "image",
          "textInput",
          "cloud",
        ].delete_if do |x|
          send(x).nil?
        end.collect do |elem|
          [nil, elem]
        end

        @item.each do
          rv << [nil, "item"]
        end

        rv
      end

      def maker_target(maker)
        maker.channel
      end

      def setup_maker_elements(channel)
        super
        [
          [skipDays, "day"],
          [skipHours, "hour"],
        ].each do |skip, key|
          if skip
            skip.__send__("#{key}s").each do |val|
              target_skips = channel.__send__("skip#{key.capitalize}s")
              new_target = target_skips.__send__("new_#{key}")
              new_target.content = val.content
            end
          end
        end
      end

      class SkipDays < Element
        include RSS09

        [
          ["day", "*"]
        ].each do |x, occurs|
          install_have_children_element(x)
          install_model(x, occurs)
        end

        def to_s(convert=true, indent=calc_indent)
          rv = tag(indent) do |next_indent|
            [
              day_elements(false, next_indent)
            ]
          end
          rv = @converter.convert(rv) if convert and @converter
          rv
        end

        private
        def children
          @day
        end

        def _tags
          @day.compact.collect do
            [nil, "day"]
          end
        end

        class Day < Element
          include RSS09

          content_setup

          def initialize(content=nil)
            super()
            @content = content
          end
      
        end
        
      end
      
      class SkipHours < Element
        include RSS09

        [
          ["hour", "*"]
        ].each do |x, occurs|
          install_have_children_element(x)
          install_model(x, occurs)
        end

        def to_s(convert=true, indent=calc_indent)
          rv = tag(indent) do |next_indent|
            [
              hour_elements(false, next_indent)
            ]
          end
          rv = @converter.convert(rv) if convert and @converter
          rv
        end

        private
        def children
          @hour
        end

        def _tags
          @hour.compact.collect do
            [nil, "hour"]
          end
        end

        class Hour < Element
          include RSS09

          content_setup

          def initialize(content=nil)
            super()
            @content = content
          end

          remove_method :content=
          def content=(value)
            @content = value.to_i
          end
          
        end
        
      end
      
      class Image < Element

        include RSS09
        
        %w(url title link).each do |x|
          install_text_element(x)
          install_model(x, nil)
        end
        %w(width height description).each do |x|
          install_text_element(x)
          install_model(x, "?")
        end

        def to_s(convert=true, indent=calc_indent)
          rv = tag(indent) do |next_indent|
            [
              url_element(false, next_indent),
              title_element(false, next_indent),
              link_element(false, next_indent),
              width_element(false, next_indent),
              height_element(false, next_indent),
              description_element(false, next_indent),
              other_element(false, next_indent),
            ]
          end
          rv = @converter.convert(rv) if convert and @converter
    	    rv
        end

        private
        def _tags
          %w(url title link width height description).delete_if do |x|
            send(x).nil?
          end.collect do |elem|
            [nil, elem]
          end
        end

        def maker_target(maker)
          maker.image
        end
      end

      class Cloud < Element

        include RSS09
        
        [
          ["domain", nil, true],
          ["port", nil, true],
          ["path", nil, true],
          ["registerProcedure", nil, true],
          ["protocol", nil ,true],
        ].each do |name, uri, required|
          install_get_attribute(name, uri, required)
        end

        def initialize(domain=nil, port=nil, path=nil, rp=nil, protocol=nil)
          super()
          @domain = domain
          @port = port
          @path = path
          @registerProcedure = rp
          @protocol = protocol
        end

        def to_s(convert=true, indent=calc_indent)
          rv = tag(indent)
          rv = @converter.convert(rv) if convert and @converter
    	    rv
        end

        private
        def _attrs
          %w(domain port path registerProcedure protocol).collect do |attr|
            [attr, true]
          end
        end

      end
      
      class Item < Element
        
        include RSS09

        %w(title link description).each do |x|
          install_text_element(x)
        end

        %w(source enclosure).each do |x|
          install_have_child_element(x)
        end

        [
          %w(category categories),
        ].each do |name, plural_name|
          install_have_children_element(name, plural_name)
        end
        
        [
          ["title", '?'],
          ["link", '?'],
          ["description", '?'],
          ["category", '*'],
          ["source", '?'],
          ["enclosure", '?'],
        ].each do |tag, occurs|
          install_model(tag, occurs)
        end

        def to_s(convert=true, indent=calc_indent)
          rv = tag(indent) do |next_indent|
            [
              title_element(false, next_indent),
              link_element(false, next_indent),
              description_element(false, next_indent),
              category_elements(false, next_indent),
              source_element(false, next_indent),
              enclosure_element(false, next_indent),
              other_element(false, next_indent),
            ]
          end
          rv = @converter.convert(rv) if convert and @converter
    	    rv
        end

        private
        def children
          [@source, @enclosure, *@category].compact
        end

        def _tags
          rv = %w(title link description author comments
            source enclosure).delete_if do |x|
            send(x).nil?
          end.collect do |x|
            [nil, x]
          end

          @category.each do
            rv << [nil, "category"]
          end
          
          rv
        end

        def maker_target(maker)
          maker.items.new_item
        end

        def setup_maker_element(item)
          super
          @enclosure.setup_maker(item) if @enclosure
          @source.setup_maker(item) if @source
        end
        
        class Source < Element

          include RSS09

          [
            ["url", nil, true]
          ].each do |name, uri, required|
            install_get_attribute(name, uri, required)
          end
          
          content_setup

          def initialize(url=nil, content=nil)
            super()
            @url = url
            @content = content
          end

          private
          def _tags
            []
          end

          def _attrs
            [
              ["url", true]
            ]
          end


          def maker_target(item)
            item.source
          end

          def setup_maker_attributes(source)
            source.url = url
            source.content = content
          end
        end

        class Enclosure < Element

          include RSS09

          [
            ["url", nil, true],
            ["length", nil, true],
            ["type", nil, true],
          ].each do |name, uri, required|
            install_get_attribute(name, uri, required)
          end

          def initialize(url=nil, length=nil, type=nil)
            super()
            @url = url
            @length = length
            @type = type
          end

          def to_s(convert=true, indent=calc_indent)
            rv = tag(indent)
            rv = @converter.convert(rv) if convert and @converter
            rv
          end

          private
          def _attrs
            [
              ["url", true],
              ["length", true],
              ["type", true],
            ]
          end

          def maker_target(item)
            item.enclosure
          end

          def setup_maker_attributes(enclosure)
            enclosure.url = url
            enclosure.length = length
            enclosure.type = type
          end
        end

        class Category < Element

          include RSS09
          
          [
            ["domain", nil, true]
          ].each do |name, uri, required|
            install_get_attribute(name, uri, required)
          end

          content_setup

          def initialize(domain=nil, content=nil)
            super()
            @domain = domain
            @content = content
          end

          private
          def _attrs
            [
              ["domain", true]
            ]
          end

          def maker_target(item)
            item.new_category
          end

          def setup_maker_attributes(category)
            category.domain = domain
            category.content = content
          end
          
        end

      end
      
      class TextInput < Element

        include RSS09

        %w(title description name link).each do |x|
          install_text_element(x)
          install_model(x, nil)
        end

        def to_s(convert=true, indent=calc_indent)
          rv = tag(indent) do |next_indent|
            [
              title_element(false, next_indent),
              description_element(false, next_indent),
              name_element(false, next_indent),
              link_element(false, next_indent),
              other_element(false, next_indent),
            ]
          end
       		rv = @converter.convert(rv) if convert and @converter
    	    rv
        end

        private
        def _tags
          %w(title description name link).each do |x|
            send(x).nil?
          end.collect do |elem|
            [nil, elem]
          end
        end

        def maker_target(maker)
          maker.textinput
        end
      end
      
    end
    
  end

  RSS09::ELEMENTS.each do |x|
    BaseListener.install_get_text_element(x, nil, "#{x}=")
  end

  module ListenerMixin
    private
    def start_rss(tag_name, prefix, attrs, ns)
      check_ns(tag_name, prefix, ns, nil)
      
      @rss = Rss.new(attrs['version'], @version, @encoding, @standalone)
      @rss.do_validate = @do_validate
      @rss.xml_stylesheets = @xml_stylesheets
      @last_element = @rss
      @proc_stack.push Proc.new { |text, tags|
        @rss.validate_for_stream(tags) if @do_validate
      }
    end
    
  end

end
