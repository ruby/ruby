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
      next_indent = indent + INDENT
      rv = <<-EOR
#{xmldecl}
#{xml_stylesheet_pi}
#{indent}<rss version="#{@rss_version}"#{ns_declaration(next_indent)}>
#{channel_element(false, next_indent)}
#{other_element(false, next_indent)}
#{indent}</rss>
EOR
      rv = @converter.convert(rv) if convert and @converter
      remove_empty_newline(rv)
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
        ["version", true],
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
        ["skipDays", "?"],
        ["skipHours", "?"],
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
        next_indent = indent + INDENT
        rv = <<-EOT
#{indent}<channel>
#{title_element(false, next_indent)}
#{link_element(false, next_indent)}
#{description_element(false, next_indent)}
#{language_element(false, next_indent)}
#{copyright_element(false, next_indent)}
#{managingEditor_element(false, next_indent)}
#{webMaster_element(false, next_indent)}
#{rating_element(false, next_indent)}
#{pubDate_element(false, next_indent)}
#{lastBuildDate_element(false, next_indent)}
#{docs_element(false, next_indent)}
#{skipDays_element(false, next_indent)}
#{skipHours_element(false, next_indent)}
#{image_element(false, next_indent)}
#{item_elements(false, next_indent)}
#{textInput_element(false, next_indent)}
#{other_element(false, next_indent)}
#{indent}</channel>
EOT
        rv = @converter.convert(rv) if convert and @converter
        rv
      end

      private
      def children
        [@image, @textInput, @cloud, *@item]
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
          next_indent = indent + INDENT
          rv = <<-EOT
#{indent}<image>
#{url_element(false, next_indent)}
#{title_element(false, next_indent)}
#{link_element(false, next_indent)}
#{width_element(false, next_indent)}
#{height_element(false, next_indent)}
#{description_element(false, next_indent)}
#{other_element(false, next_indent)}
#{indent}</image>
EOT
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
          next_indent = indent + INDENT
          rv = <<-EOT
#{indent}<cloud
#{next_indent}domain="#{h @domain}"
#{next_indent}port="#{h @port}"
#{next_indent}path="#{h @path}"
#{next_indent}registerProcedure="#{h @registerProcedure}"
#{next_indent}protocol="#{h @protocol}"/>
EOT
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

        %w(category source enclosure).each do |x|
          install_have_child_element(x)
        end

        [
          ["title", '?'],
          ["link", '?'],
          ["description", '?'],
          ["category", '?'],
          ["source", '?'],
          ["enclosure", '?'],
        ].each do |tag, occurs|
          install_model(tag, occurs)
        end

        def to_s(convert=true, indent=calc_indent)
          next_indent = indent + INDENT
          rv = <<-EOT
#{indent}<item>
#{title_element(false, next_indent)}
#{link_element(false, next_indent)}
#{description_element(false, next_indent)}
#{category_element(false, next_indent)}
#{source_element(false, next_indent)}
#{enclosure_element(false, next_indent)}
#{other_element(false, next_indent)}
#{indent}</item>
EOT
       		rv = @converter.convert(rv) if convert and @converter
    	    rv
        end

        private
        def children
          [@category, @source, @enclosure,].compact
        end

        def _tags
          %w(title link description author comments category
            source enclosure).delete_if do |x|
            send(x).nil?
          end.collect do |x|
            [nil, x]
          end
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

          def to_s(convert=true, indent=calc_indent)
            if @url
              rv = %Q!				<source url="#{@url}">!
              rv << %Q!#{@content}</source>!
              rv = @converter.convert(rv) if convert and @converter
              rv
            else
              ''
            end
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
            if @url and @length and @type
              rv = %Q!<enclosure url="#{h @url}" !
              rv << %Q!length="#{h @length}" type="#{h @type}"/>!
              rv = @converter.convert(rv) if convert and @converter
              rv
            else
              ''
            end
          end

          private
          def _attrs
            [
              ["url", true],
              ["length", true],
              ["type", true],
            ]
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

          def to_s(convert=true, indent=calc_indent)
            if @domain
              rv = %Q!<category domain="#{h @domain}">!
              rv << %Q!#{h @content}</category>!
              rv = @converter.convert(rv) if convert and @converter
              rv
            else
              ''
            end
          end

          private
          def _attrs
            [
              ["domain", true]
            ]
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
          next_indent = indent + INDENT
          rv = <<-EOT
#{indent}<textInput>
#{title_element(false, next_indent)}
#{description_element(false, next_indent)}
#{name_element(false, next_indent)}
#{link_element(false, next_indent)}
#{other_element(false, next_indent)}
#{indent}</textInput>
EOT
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
