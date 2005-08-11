require "rss/parser"

module RSS

  module RSS10
    NSPOOL = {}
    ELEMENTS = []

    def self.append_features(klass)
      super
      
      klass.install_must_call_validator('', ::RSS::URI)
    end

  end

  class RDF < Element

    include RSS10
    include RootElementMixin

    class << self

      def required_uri
        URI
      end

    end

    @tag_name = 'RDF'

    PREFIX = 'rdf'
    URI = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    install_ns('', ::RSS::URI)
    install_ns(PREFIX, URI)

    [
      ["channel", nil],
      ["image", "?"],
      ["item", "+"],
      ["textinput", "?"],
    ].each do |tag, occurs|
      install_model(tag, occurs)
    end

    %w(channel image textinput).each do |name|
      install_have_child_element(name)
    end

    install_have_children_element("item")

    attr_accessor :rss_version, :version, :encoding, :standalone
    
    def initialize(version=nil, encoding=nil, standalone=nil)
      super('1.0', version, encoding, standalone)
    end

    def full_name
      tag_name_with_prefix(PREFIX)
    end
    
    def to_s(need_convert=true, indent=calc_indent)
      rv = tag(indent, ns_declarations) do |next_indent|
        [
          channel_element(false, next_indent),
          image_element(false, next_indent),
          item_elements(false, next_indent),
          textinput_element(false, next_indent),
          other_element(false, next_indent),
        ]
      end
      rv = convert(rv) if need_convert
      rv
    end

    private
    def rdf_validate(tags)
      _validate(tags, [])
    end

    def children
      [@channel, @image, @textinput, *@item]
    end

    def _tags
      rv = [
        [::RSS::URI, "channel"],
        [::RSS::URI, "image"],
      ].delete_if {|uri, name| send(name).nil?}
      @item.each do |item|
        rv << [::RSS::URI, "item"]
      end
      rv << [::RSS::URI, "textinput"] if @textinput
      rv
    end

    class Seq < Element

      include RSS10

      class << self
        
        def required_uri
          URI
        end
        
      end

      @tag_name = 'Seq'
      
      install_have_children_element("li")
      
      install_must_call_validator('rdf', ::RSS::RDF::URI)
      
      def initialize(li=[])
        super()
        @li = li
      end
      
      def to_s(need_convert=true, indent=calc_indent)
        tag(indent) do |next_indent|
          [
            li_elements(need_convert, next_indent),
            other_element(need_convert, next_indent),
          ]
        end
      end

      def full_name
        tag_name_with_prefix(PREFIX)
      end
      
      private
      def children
        @li
      end
          
      def rdf_validate(tags)
        _validate(tags, [["li", '*']])
      end

      def _tags
        rv = []
        @li.each do |li|
          rv << [URI, "li"]
        end
        rv
      end

    end

    class Li < Element

      include RSS10

      class << self
          
        def required_uri
          URI
        end
        
      end
      
      [
        ["resource", [URI, nil], true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end
      
      def initialize(resource=nil)
        super()
        @resource = resource
      end

      def full_name
        tag_name_with_prefix(PREFIX)
      end
      
      def to_s(need_convert=true, indent=calc_indent)
        rv = tag(indent)
        rv = convert(rv) if need_convert
        rv
      end

      private
      def _attrs
        [
          ["resource", true]
        ]
      end
      
    end

    class Channel < Element

      include RSS10
      
      class << self

        def required_uri
          ::RSS::URI
        end

      end

      [
        ["about", URI, true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end

      %w(title link description).each do |name|
        install_text_element(name)
      end

      %w(image items textinput).each do |name|
        install_have_child_element(name)
      end
      
      [
        ['title', nil],
        ['link', nil],
        ['description', nil],
        ['image', '?'],
        ['items', nil],
        ['textinput', '?'],
      ].each do |tag, occurs|
        install_model(tag, occurs)
      end
      
      def initialize(about=nil)
        super()
        @about = about
      end

      def to_s(need_convert=true, indent=calc_indent)
        rv = tag(indent) do |next_indent|
          [
            title_element(false, next_indent),
            link_element(false, next_indent),
            description_element(false, next_indent),
            image_element(false, next_indent),
            items_element(false, next_indent),
            textinput_element(false, next_indent),
            other_element(false, next_indent),
          ]
        end
        rv = convert(rv) if need_convert
        rv
      end

      private
      def children
        [@image, @items, @textinput]
      end

      def _tags
        [
          [::RSS::URI, 'title'],
          [::RSS::URI, 'link'],
          [::RSS::URI, 'description'],
          [::RSS::URI, 'image'],
          [::RSS::URI, 'items'],
          [::RSS::URI, 'textinput'],
        ].delete_if do |uri, name|
          send(name).nil?
        end
      end

      def _attrs
        [
          ["#{PREFIX}:about", true, "about"]
        ]
      end
      
      def maker_target(maker)
        maker.channel
      end
      
      def setup_maker_attributes(channel)
        channel.about = about
      end

      class Image < Element
        
        include RSS10

        class << self
          
          def required_uri
            ::RSS::URI
          end

        end

        [
          ["resource", URI, true]
        ].each do |name, uri, required|
          install_get_attribute(name, uri, required)
        end
      
        def initialize(resource=nil)
          super()
          @resource = resource
        end

        def to_s(need_convert=true, indent=calc_indent)
          rv = tag(indent)
          rv = convert(rv) if need_convert
          rv
        end

        private
        def _attrs
          [
            ["#{PREFIX}:resource", true, "resource"]
          ]
        end
      end

      class Textinput < Element
        
        include RSS10

        class << self
          
          def required_uri
            ::RSS::URI
          end

        end

        [
          ["resource", URI, true]
        ].each do |name, uri, required|
          install_get_attribute(name, uri, required)
        end
      
        def initialize(resource=nil)
          super()
          @resource = resource
        end

        def to_s(need_convert=true, indent=calc_indent)
          rv = tag(indent)
          rv = convert(rv) if need_convert
          rv
        end
        
        private
        def _attrs
          [
            ["#{PREFIX}:resource", true, "resource"]
          ]
        end
      end
      
      class Items < Element

        include RSS10

        Seq = ::RSS::RDF::Seq
        class Seq
          unless const_defined?(:Li)
            Li = ::RSS::RDF::Li
          end
        end

        class << self
          
          def required_uri
            ::RSS::URI
          end
          
        end

        install_have_child_element("Seq")
        
        install_must_call_validator('rdf', ::RSS::RDF::URI)
        
        def initialize(seq=Seq.new)
          super()
          @Seq = seq
        end
        
        def to_s(need_convert=true, indent=calc_indent)
          rv = tag(indent) do |next_indent|
            [
              Seq_element(need_convert, next_indent),
              other_element(need_convert, next_indent),
            ]
          end
        end

        private
        def children
          [@Seq]
        end

        private
        def _tags
          rv = []
          rv << [URI, 'Seq'] unless @Seq.nil?
          rv
        end
        
        def rdf_validate(tags)
          _validate(tags, [["Seq", nil]])
        end

      end

    end

    class Image < Element

      include RSS10

      class << self
        
        def required_uri
          ::RSS::URI
        end

      end
      
      [
        ["about", URI, true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end

      %w(title url link).each do |name|
        install_text_element(name)
      end
    
      [
        ['title', nil],
        ['url', nil],
        ['link', nil],
      ].each do |tag, occurs|
        install_model(tag, occurs)
      end

      def initialize(about=nil)
        super()
        @about = about
      end

      def to_s(need_convert=true, indent=calc_indent)
        rv = tag(indent) do |next_indent|
          [
            title_element(false, next_indent),
            url_element(false, next_indent),
            link_element(false, next_indent),
            other_element(false, next_indent),
          ]
        end
        rv = convert(rv) if need_convert
        rv
      end

      private
      def _tags
        [
          [::RSS::URI, 'title'],
          [::RSS::URI, 'url'],
          [::RSS::URI, 'link'],
        ].delete_if do |uri, name|
          send(name).nil?
        end
      end

      def _attrs
        [
          ["#{PREFIX}:about", true, "about"]
        ]
      end

      def maker_target(maker)
        maker.image
      end
    end

    class Item < Element

      include RSS10

      class << self

        def required_uri
          ::RSS::URI
        end
        
      end

      [
        ["about", URI, true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end

      %w(title link description).each do |name|
        install_text_element(name)
      end

      [
        ["title", nil],
        ["link", nil],
        ["description", "?"],
      ].each do |tag, occurs|
        install_model(tag, occurs)
      end

      def initialize(about=nil)
        super()
        @about = about
      end

      def to_s(need_convert=true, indent=calc_indent)
        rv = tag(indent) do |next_indent|
          [
            title_element(false, next_indent),
            link_element(false, next_indent),
            description_element(false, next_indent),
            other_element(false, next_indent),
          ]
        end
        rv = convert(rv) if need_convert
        rv
      end
 
      private
      def _tags
        [
          [::RSS::URI, 'title'],
          [::RSS::URI, 'link'],
          [::RSS::URI, 'description'],
        ].delete_if do |uri, name|
          send(name).nil?
        end
      end

      def _attrs
        [
          ["#{PREFIX}:about", true, "about"]
        ]
      end

      def maker_target(maker)
        maker.items.new_item
      end
    end

    class Textinput < Element

      include RSS10

      class << self

        def required_uri
          ::RSS::URI
        end

      end

      [
        ["about", URI, true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end

      %w(title description name link).each do |name|
        install_text_element(name)
      end
    
      [
        ["title", nil],
        ["description", nil],
        ["name", nil],
        ["link", nil],
      ].each do |tag, occurs|
        install_model(tag, occurs)
      end

      def initialize(about=nil)
        super()
        @about = about
      end

      def to_s(need_convert=true, indent=calc_indent)
        rv = tag(indent) do |next_indent|
          [
            title_element(false, next_indent),
            description_element(false, next_indent),
            name_element(false, next_indent),
            link_element(false, next_indent),
            other_element(false, next_indent),
          ]
        end
        rv = convert(rv) if need_convert
        rv
      end

      private
      def _tags
        [
          [::RSS::URI, 'title'],
          [::RSS::URI, 'description'],
          [::RSS::URI, 'name'],
          [::RSS::URI, 'link'],
        ].delete_if do |uri, name|
          send(name).nil?
        end
      end
      
      def _attrs
        [
          ["#{PREFIX}:about", true, "about"]
        ]
      end

      def maker_target(maker)
        maker.textinput
      end
    end

  end

  RSS10::ELEMENTS.each do |name|
    BaseListener.install_get_text_element(URI, name, "#{name}=")
  end

  module ListenerMixin
    private
    def start_RDF(tag_name, prefix, attrs, ns)
      check_ns(tag_name, prefix, ns, RDF::URI)

      @rss = RDF.new(@version, @encoding, @standalone)
      @rss.do_validate = @do_validate
      @rss.xml_stylesheets = @xml_stylesheets
      @last_element = @rss
      @proc_stack.push Proc.new { |text, tags|
        @rss.validate_for_stream(tags) if @do_validate
      }
    end
  end

end
