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
              OTHER_ELEMENTS + super
            end

            def self.need_initialize_variables
              NEED_INITIALIZE_VARIABLES + super
            end
          EOEOC
        end

        def self.add_other_element(variable_name)
          OTHER_ELEMENTS << variable_name
        end

        def self.other_elements
          OTHER_ELEMENTS
        end

        def self.add_need_initialize_variable(variable_name, init_value="nil")
          NEED_INITIALIZE_VARIABLES << [variable_name, init_value]
        end

        def self.need_initialize_variables
          NEED_INITIALIZE_VARIABLES
        end

        def self.def_array_element(name, plural=nil, klass=nil)
          include Enumerable
          extend Forwardable

          plural ||= "\#{name}s"
          klass ||= "self.class::\#{Utils.to_class_name(name)}"

          def_delegators("@\#{plural}", :<<, :[], :[]=, :first, :last)
          def_delegators("@\#{plural}", :push, :pop, :shift, :unshift)
          def_delegators("@\#{plural}", :each, :size, :empty?, :clear)

          add_need_initialize_variable(plural, "[]")

          module_eval(<<-EOM, __FILE__, __LINE__ + 1)
            def new_\#{name}
              \#{name} = \#{klass}.new(@maker)
              @\#{plural} << \#{name}
              if block_given?
                yield \#{name}
              else
                \#{name}
              end
            end
            alias new_child new_\#{name}

            def to_feed(*args)
              @\#{plural}.each do |\#{name}|
                \#{name}.to_feed(*args)
              end
            end

            def replace(elements)
              @\#{plural}.replace(elements.to_a)
            end
EOM
        end
        EOC
      end
      
      attr_reader :maker
      def initialize(maker)
        @maker = maker
        @default_values_are_set = false
        initialize_variables
      end

      def have_required_values?
        not_set_required_variables.empty?
      end

      def variable_is_set?
        variables.any? {|var| not __send__(var).nil?}
      end

      private
      def initialize_variables
        self.class.need_initialize_variables.each do |variable_name, init_value|
          instance_eval("@#{variable_name} = #{init_value}", __FILE__, __LINE__)
        end
      end

      def setup_other_elements(feed, current=nil)
        current ||= current_element(feed)
        self.class.other_elements.each do |element|
          __send__("setup_#{element}", feed, current)
        end
      end

      def current_element(feed)
        feed
      end

      def set_default_values(&block)
        return yield if @default_values_are_set

        begin
          @default_values_are_set = true
          _set_default_values(&block)
        ensure
          @default_values_are_set = false
        end
      end

      def _set_default_values(&block)
        yield
      end

      def setup_values(target)
        set = false
        if have_required_values?
          variables.each do |var|
            setter = "#{var}="
            if target.respond_to?(setter)
              value = __send__(var)
              if value
                target.__send__(setter, value)
                set = true
              end
            end
          end
        end
        set
      end

      def set_parent(target, parent)
        target.parent = parent if target.class.need_parent?
      end

      def variables
        self.class.need_initialize_variables.find_all do |name, init|
          "nil" == init
        end.collect do |name, init|
          name
        end
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

    module AtomPersonConstructBase
      def self.append_features(klass)
        super

        klass.class_eval(<<-EOC, __FILE__, __LINE__ + 1)
          %w(name uri email).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
EOC
      end
    end

    module AtomTextConstructBase
      module EnsureXMLContent
        def ensure_xml_content(content)
          xhtml_uri = ::RSS::Atom::XHTML_URI
          unless content.is_a?(RSS::XML::Element) and
              ["div", xhtml_uri] == [content.name, content.uri]
            children = content
            children = [children] unless content.is_a?(Array)
            children = set_xhtml_uri_as_default_uri(children)
            content = RSS::XML::Element.new("div", nil, xhtml_uri,
                                            {"xmlns" => xhtml_uri},
                                            children)
          end
          content
        end

        private
        def set_xhtml_uri_as_default_uri(children)
          children.collect do |child|
            if child.is_a?(RSS::XML::Element) and
                child.prefix.nil? and child.uri.nil?
              RSS::XML::Element.new(child.name, nil, ::RSS::Atom::XHTML_URI,
                                    child.attributes.dup,
                                    set_xhtml_uri_as_default_uri(child.children))
            else
              child
            end
          end
        end
      end

      def self.append_features(klass)
        super

        klass.class_eval(<<-EOC, __FILE__, __LINE__ + 1)
          include EnsureXMLContent

          %w(type content xml_content).each do |element|
            attr element, element != "xml_content"
            add_need_initialize_variable(element)
          end

          def xml_content=(content)
            @xml_content = ensure_xml_content(content)
          end

          alias_method(:xhtml, :xml_content)
          alias_method(:xhtml=, :xml_content=)
EOC
      end
    end

    module SetupDefaultDate
      private
      def _set_default_values(&block)
        keep = {
          :date => date,
          :dc_dates => dc_dates.to_a.dup,
        }
        _date = date
        if _date and !dc_dates.any? {|dc_date| dc_date.value == _date}
          dc_date = self.class::DublinCoreDates::Date.new(self)
          dc_date.value = _date.dup
          dc_dates.unshift(dc_date)
        end
        self.date ||= self.dc_date
        super(&block)
      ensure
        date = keep[:date]
        dc_dates.replace(keep[:dc_dates])
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
          def setup_#{element}(feed)
            @#{element}.to_feed(feed)
          end

          def make_#{element}
            self.class::#{Utils.to_class_name(element)}.new(self)
          end
EOC
      end
      
      attr_reader :feed_version
      alias_method(:rss_version, :feed_version)
      attr_accessor :version, :encoding, :standalone

      def initialize(feed_version)
        super(self)
        @feed_type = nil
        @feed_subtype = nil
        @feed_version = feed_version
        @version = "1.0"
        @encoding = "UTF-8"
        @standalone = nil
      end
      
      def make
        if block_given?
          yield(self)
          to_feed
        else
          nil
        end
      end

      def to_feed
        feed = make_feed
        setup_xml_stylesheets(feed)
        setup_elements(feed)
        setup_other_elements(feed)
        if feed.valid?
          feed
        else
          nil
        end
      end
      
      private
      remove_method :make_xml_stylesheets
      def make_xml_stylesheets
        XMLStyleSheets.new(self)
      end
    end

    class XMLStyleSheets
      include Base

      def_array_element("xml_stylesheet", nil, "XMLStyleSheet")

      class XMLStyleSheet
        include Base

        ::RSS::XMLStyleSheet::ATTRIBUTES.each do |attribute|
          attr_accessor attribute
          add_need_initialize_variable(attribute)
        end
        
        def to_feed(feed)
          xss = ::RSS::XMLStyleSheet.new
          guess_type_if_need(xss)
          set = setup_values(xss)
          if set
            feed.xml_stylesheets << xss
          end
        end

        private
        def guess_type_if_need(xss)
          if @type.nil?
            xss.href = @href
            @type = xss.type
          end
        end

        def required_variable_names
          %w(href type)
        end
      end
    end
    
    class ChannelBase
      include Base
      include SetupDefaultDate

      %w(cloud categories skipDays skipHours links authors
         contributors generator copyright description
         title).each do |element|
        attr_reader element
        add_other_element(element)
        add_need_initialize_variable(element, "make_#{element}")
        module_eval(<<-EOC, __FILE__, __LINE__)
          private
          def setup_#{element}(feed, current)
            @#{element}.to_feed(feed, current)
          end

          def make_#{element}
            self.class::#{Utils.to_class_name(element)}.new(@maker)
          end
EOC
      end

      %w(id about language
         managingEditor webMaster rating docs date
         lastBuildDate ttl).each do |element|
        attr_accessor element
        add_need_initialize_variable(element)
      end

      def pubDate
        date
      end

      def pubDate=(date)
        self.date = date
      end

      def updated
        date
      end

      def updated=(date)
        self.date = date
      end

      def link
        _link = links.first
        _link ? _link.href : nil
      end

      def link=(href)
        _link = links.first || links.new_link
        _link.rel = "self"
        _link.href = href
      end

      def author
        _author = authors.first
        _author ? _author.name : nil
      end

      def author=(name)
        _author = authors.first || authors.new_author
        _author.name = name
      end

      def contributor
        _contributor = contributors.first
        _contributor ? _contributor.name : nil
      end

      def contributor=(name)
        _contributor = contributors.first || contributors.new_contributor
        _contributor.name = name
      end

      def generator=(content)
        @generator.content = content
      end

      def copyright=(content)
        @copyright.content = content
      end

      alias_method(:rights, :copyright)
      alias_method(:rights=, :copyright=)

      def description=(content)
        @description.content = content
      end

      alias_method(:subtitle, :description)
      alias_method(:subtitle=, :description=)

      def title=(content)
        @title.content = content
      end

      def icon
        image_favicon.about
      end

      def icon=(url)
        image_favicon.about = url
      end

      def logo
        maker.image.url
      end

      def logo=(url)
        maker.image.url = url
      end

      class SkipDaysBase
        include Base

        def_array_element("day")

        class DayBase
          include Base
          
          %w(content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end
      end
      
      class SkipHoursBase
        include Base

        def_array_element("hour")

        class HourBase
          include Base
          
          %w(content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end
      end
      
      class CloudBase
        include Base
        
        %w(domain port path registerProcedure protocol).each do |element|
          attr_accessor element
          add_need_initialize_variable(element)
        end
      end

      class CategoriesBase
        include Base

        def_array_element("category", "categories")

        class CategoryBase
          include Base

          %w(domain content label).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end

          alias_method(:term, :domain)
          alias_method(:term=, :domain=)
          alias_method(:scheme, :content)
          alias_method(:scheme=, :content=)
        end
      end

      class LinksBase
        include Base

        def_array_element("link")

        class LinkBase
          include Base

          %w(href rel type hreflang title length).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end
      end

      class AuthorsBase
        include Base

        def_array_element("author")

        class AuthorBase
          include Base
          include AtomPersonConstructBase
        end
      end

      class ContributorsBase
        include Base

        def_array_element("contributor")

        class ContributorBase
          include Base
          include AtomPersonConstructBase
        end
      end

      class GeneratorBase
        include Base

        %w(uri version content).each do |element|
          attr_accessor element
          add_need_initialize_variable(element)
        end
      end

      class CopyrightBase
        include Base
        include AtomTextConstructBase
      end

      class DescriptionBase
        include Base
        include AtomTextConstructBase
      end

      class TitleBase
        include Base
        include AtomTextConstructBase
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
    end
    
    class ItemsBase
      include Base

      def_array_element("item")

      attr_accessor :do_sort, :max_size
      
      def initialize(maker)
        super
        @do_sort = false
        @max_size = -1
      end
      
      def normalize
        if @max_size >= 0
          sort_if_need[0...@max_size]
        else
          sort_if_need[0..@max_size]
        end
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
        include SetupDefaultDate

        %w(guid enclosure source categories authors links
           contributors rights description content title).each do |element|
          attr_reader element
          add_other_element(element)
          add_need_initialize_variable(element, "make_#{element}")
          module_eval(<<-EOC, __FILE__, __LINE__)
          private
          def setup_#{element}(feed, current)
            @#{element}.to_feed(feed, current)
          end

          def make_#{element}
            self.class::#{Utils.to_class_name(element)}.new(@maker)
          end
EOC
        end

        %w(date comments id published).each do |element|
          attr_accessor element
          add_need_initialize_variable(element)
        end

        def pubDate
          date
        end

        def pubDate=(date)
          self.date = date
        end

        def updated
          date
        end

        def updated=(date)
          self.date = date
        end

        def author
          _link = authors.first
          _link ? _author.name : nil
        end

        def author=(name)
          _author = authors.first || authors.new_author
          _author.name = name
        end

        def link
          _link = links.first
          _link ? _link.href : nil
        end

        def link=(href)
          _link = links.first || links.new_link
          _link.rel = "alternate"
          _link.href = href
        end

        def rights=(content)
          @rights.content = content
        end

        def description=(content)
          @description.content = content
        end

        alias_method(:summary, :description)
        alias_method(:summary=, :description=)

        def title=(content)
          @title.content = content
        end

        def <=>(other)
          _date = date || dc_date
          _other_date = other.date || other.dc_date
          if _date and _other_date
            _date <=> _other_date
          elsif _date
            1
          elsif _other_date
            -1
          else
            0
          end
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

          %w(authors categories contributors generator icon
             links logo rights subtitle title).each do |element|
            attr_reader element
            add_other_element(element)
            add_need_initialize_variable(element, "make_#{element}")
            module_eval(<<-EOC, __FILE__, __LINE__)
            private
            def setup_#{element}(feed, current)
              @#{element}.to_feed(feed, current)
            end

            def make_#{element}
              self.class::#{Utils.to_class_name(element)}.new(@maker)
            end
            EOC
          end

          %w(id content date).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end

          def url
            link = links.first
            link ? link.href : nil
          end

          def url=(value)
            link = links.first || links.new_link
            link.href = value
          end

          def updated
            date
          end

          def updated=(date)
            self.date = date
          end

          private
          AuthorsBase = ChannelBase::AuthorsBase
          CategoriesBase = ChannelBase::CategoriesBase
          ContributorsBase = ChannelBase::ContributorsBase
          GeneratorBase = ChannelBase::GeneratorBase

          class IconBase
            include Base

            %w(url).each do |element|
              attr_accessor element
              add_need_initialize_variable(element)
            end
          end

          LinksBase = ChannelBase::LinksBase

          class LogoBase
            include Base

            %w(uri).each do |element|
              attr_accessor element
              add_need_initialize_variable(element)
            end
          end

          class RightsBase
            include Base
            include AtomTextConstructBase
          end

          class SubtitleBase
            include Base
            include AtomTextConstructBase
          end

          class TitleBase
            include Base
            include AtomTextConstructBase
          end
        end

        CategoriesBase = ChannelBase::CategoriesBase
        AuthorsBase = ChannelBase::AuthorsBase
        LinksBase = ChannelBase::LinksBase
        ContributorsBase = ChannelBase::ContributorsBase

        class RightsBase
          include Base
          include AtomTextConstructBase
        end

        class DescriptionBase
          include Base
          include AtomTextConstructBase
        end

        class ContentBase
          include Base
          include AtomTextConstructBase::EnsureXMLContent

          %w(type src content xml_content).each do |element|
            attr element, element != "xml_content"
            add_need_initialize_variable(element)
          end

          def xml_content=(content)
            content = ensure_xml_content(content) if inline_xhtml?
            @xml_content = content
          end

          alias_method(:xhtml, :xml_content)
          alias_method(:xhtml=, :xml_content=)

          alias_method(:xml, :xml_content)
          alias_method(:xml=, :xml_content=)

          private
          def inline_text?
            [nil, "text", "html"].include?(@type)
          end

          def inline_html?
            @type == "html"
          end

          def inline_xhtml?
            @type == "xhtml"
          end

          def inline_other?
            !out_of_line? and ![nil, "text", "html", "xhtml"].include?(@type)
          end

          def inline_other_text?
            return false if @type.nil? or out_of_line?
            /\Atext\//i.match(@type) ? true : false
          end

          def inline_other_xml?
            return false if @type.nil? or out_of_line?
            /[\+\/]xml\z/i.match(@type) ? true : false
          end

          def inline_other_base64?
            return false if @type.nil? or out_of_line?
            @type.include?("/") and !inline_other_text? and !inline_other_xml?
          end

          def out_of_line?
            not @src.nil? and @content.nil?
          end
        end

        class TitleBase
          include Base
          include AtomTextConstructBase
        end
      end
    end

    class TextinputBase
      include Base

      %w(title description name link).each do |element|
        attr_accessor element
        add_need_initialize_variable(element)
      end
    end
  end
end
