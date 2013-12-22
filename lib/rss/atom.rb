require 'rss/parser'

module RSS
  ##
  # Atom is an XML-based document format that is used to describe 'feeds' of related information.
  # A typical use is in a news feed where the information is periodically updated and which users
  # can subscribe to.  The Atom format is described in http://tools.ietf.org/html/rfc4287
  #
  # The Atom module provides support in reading and creating feeds.
  #
  # See the RSS module for examples consuming and creating feeds.
  module Atom

    ##
    # The Atom URI W3C Namespace

    URI = "http://www.w3.org/2005/Atom"

    ##
    # The XHTML URI W3C Namespace

    XHTML_URI = "http://www.w3.org/1999/xhtml"

    module CommonModel
      NSPOOL = {}
      ELEMENTS = []

      def self.append_features(klass)
        super
        klass.install_must_call_validator("atom", URI)
        [
         ["lang", :xml],
         ["base", :xml],
        ].each do |name, uri, required|
          klass.install_get_attribute(name, uri, required, [nil, :inherit])
        end
        klass.class_eval do
          class << self
            def required_uri
              URI
            end

            def need_parent?
              true
            end
          end
        end
      end
    end

    module ContentModel
      module ClassMethods
        def content_type
          @content_type ||= nil
        end
      end

      class << self
        def append_features(klass)
          super
          klass.extend(ClassMethods)
          klass.content_setup(klass.content_type, klass.tag_name)
        end
      end

      def maker_target(target)
        target
      end

      private
      def setup_maker_element_writer
        "#{self.class.name.split(/::/).last.downcase}="
      end

      def setup_maker_element(target)
        target.__send__(setup_maker_element_writer, content)
        super
      end
    end

    module URIContentModel
      class  << self
        def append_features(klass)
          super
          klass.class_eval do
            @content_type = [nil, :uri]
            include(ContentModel)
          end
        end
      end
    end

    # The TextConstruct module is used to define a Text construct Atom element,
    # which is used to store small quantities of human-readable text
    #
    # The TextConstruct has a type attribute, e.g. text, html, xhtml
    module TextConstruct
      def self.append_features(klass)
        super
        klass.class_eval do
          [
           ["type", ""],
          ].each do |name, uri, required|
            install_get_attribute(name, uri, required, :text_type)
          end

          content_setup
          add_need_initialize_variable("xhtml")

          class << self
            def xml_getter
              "xhtml"
            end

            def xml_setter
              "xhtml="
            end
          end
        end
      end

      attr_writer :xhtml

      def xhtml
        return @xhtml if @xhtml.nil?
        if @xhtml.is_a?(XML::Element) and
            [@xhtml.name, @xhtml.uri] == ["div", XHTML_URI]
          return @xhtml
        end

        children = @xhtml
        children = [children] unless children.is_a?(Array)
        XML::Element.new("div", nil, XHTML_URI,
                         {"xmlns" => XHTML_URI}, children)
      end

      # Returns true if type is "xhtml"
      def have_xml_content?
        @type == "xhtml"
      end

      def atom_validate(ignore_unknown_element, tags, uri)
        if have_xml_content?
          if @xhtml.nil?
            raise MissingTagError.new("div", tag_name)
          end
          unless [@xhtml.name, @xhtml.uri] == ["div", XHTML_URI]
            raise NotExpectedTagError.new(@xhtml.name, @xhtml.uri, tag_name)
          end
        end
      end

      private
      def maker_target(target)
        target.__send__(self.class.name.split(/::/).last.downcase) {|x| x}
      end

      def setup_maker_attributes(target)
        target.type = type
        target.content = content
        target.xml_content = @xhtml
      end
    end

    # The PersonConstruct module is used to define a Person Atom element that can be
    # used to describe a person, corporation, or similar entity
    #
    # The PersonConstruct has a Name, Uri, and Email child elements
    module PersonConstruct

      # Adds attributes for name, uri, and email to the +klass+
      def self.append_features(klass)
        super
        klass.class_eval do
          [
           ["name", nil],
           ["uri", "?"],
           ["email", "?"],
          ].each do |tag, occurs|
            install_have_attribute_element(tag, URI, occurs, nil, :content)
          end
        end
      end

      def maker_target(target)
        target.__send__("new_#{self.class.name.split(/::/).last.downcase}")
      end

      # The name of the person or entity
      class Name < RSS::Element
        include CommonModel
        include ContentModel
      end

      # The URI of the person or entity
      class Uri < RSS::Element
        include CommonModel
        include URIContentModel
      end

      # The email of the person or entity
      class Email < RSS::Element
        include CommonModel
        include ContentModel
      end
    end

    # Element used to describe an Atom date and time in the ISO 8601 format
    #
    # Examples:
    # * 2013-03-04T15:30:02Z
    # * 2013-03-04T10:30:02-05:00
    module DateConstruct
      def self.append_features(klass)
        super
        klass.class_eval do
          @content_type = :w3cdtf
          include(ContentModel)
        end
      end

      # Raises NotAvailableValueError if element content is nil
      def atom_validate(ignore_unknown_element, tags, uri)
        raise NotAvailableValueError.new(tag_name, "") if content.nil?
      end
    end

    module DuplicateLinkChecker
      # Checks if there are duplicate links with the same type and hreflang attributes
      # that have an alternate (or empty) rel attribute
      #
      # Raises a TooMuchTagError if there are duplicates found
      def validate_duplicate_links(links)
        link_infos = {}
        links.each do |link|
          rel = link.rel || "alternate"
          next unless rel == "alternate"
          key = [link.hreflang, link.type]
          if link_infos.has_key?(key)
            raise TooMuchTagError.new("link", tag_name)
          end
          link_infos[key] = true
        end
      end
    end

    # Atom feed element
    #
    # A Feed has several metadata attributes in addition to a number of Entry child elements
    class Feed < RSS::Element
      include RootElementMixin
      include CommonModel
      include DuplicateLinkChecker

      install_ns('', URI)

      [
       ["author", "*", :children],
       ["category", "*", :children, "categories"],
       ["contributor", "*", :children],
       ["generator", "?"],
       ["icon", "?", nil, :content],
       ["id", nil, nil, :content],
       ["link", "*", :children],
       ["logo", "?"],
       ["rights", "?"],
       ["subtitle", "?", nil, :content],
       ["title", nil, nil, :content],
       ["updated", nil, nil, :content],
       ["entry", "*", :children, "entries"],
      ].each do |tag, occurs, type, *args|
        type ||= :child
        __send__("install_have_#{type}_element",
                 tag, URI, occurs, tag, *args)
      end

      # Creates a new Atom feed
      def initialize(version=nil, encoding=nil, standalone=nil)
        super("1.0", version, encoding, standalone)
        @feed_type = "atom"
        @feed_subtype = "feed"
      end

      alias_method :items, :entries

      # Returns true if there are any authors for the feed or any of the Entry
      # child elements have an author
      def have_author?
        authors.any? {|author| !author.to_s.empty?} or
          entries.any? {|entry| entry.have_author?(false)}
      end

      private
      def atom_validate(ignore_unknown_element, tags, uri)
        unless have_author?
          raise MissingTagError.new("author", tag_name)
        end
        validate_duplicate_links(links)
      end

      def have_required_elements?
        super and have_author?
      end

      def maker_target(maker)
        maker.channel
      end

      def setup_maker_element(channel)
        prev_dc_dates = channel.dc_dates.to_a.dup
        super
        channel.about = id.content if id
        channel.dc_dates.replace(prev_dc_dates)
      end

      def setup_maker_elements(channel)
        super
        items = channel.maker.items
        entries.each do |entry|
          entry.setup_maker(items)
        end
      end

      class Author < RSS::Element
        include CommonModel
        include PersonConstruct
      end

      class Category < RSS::Element
        include CommonModel

        [
         ["term", "", true],
         ["scheme", "", false, [nil, :uri]],
         ["label", ""],
        ].each do |name, uri, required, type|
          install_get_attribute(name, uri, required, type)
        end

        private
        def maker_target(target)
          target.new_category
        end
      end

      class Contributor < RSS::Element
        include CommonModel
        include PersonConstruct
      end

      class Generator < RSS::Element
        include CommonModel
        include ContentModel

        [
         ["uri", "", false, [nil, :uri]],
         ["version", ""],
        ].each do |name, uri, required, type|
          install_get_attribute(name, uri, required, type)
        end

        private
        def setup_maker_attributes(target)
          target.generator do |generator|
            generator.uri = uri if uri
            generator.version = version if version
          end
        end
      end

      # Atom Icon element
      #
      # Image that provides a visual identification for the Feed.  Image should have an aspect
      # ratio of 1:1
      class Icon < RSS::Element
        include CommonModel
        include URIContentModel
      end

      # Atom ID element
      #
      # Universally Unique Identifier (UUID) for the Feed
      class Id < RSS::Element
        include CommonModel
        include URIContentModel
      end

      # Defines an Atom Link element
      #
      # A Link has the following attributes:
      # * href
      # * rel
      # * type
      # * hreflang
      # * title
      # * length
      class Link < RSS::Element
        include CommonModel

        [
         ["href", "", true, [nil, :uri]],
         ["rel", ""],
         ["type", ""],
         ["hreflang", ""],
         ["title", ""],
         ["length", ""],
        ].each do |name, uri, required, type|
          install_get_attribute(name, uri, required, type)
        end

        private
        def maker_target(target)
          target.new_link
        end
      end

      # Atom Logo element
      #
      # Image that provides a visual identification for the Feed.  Image should have an aspect
      # ratio of 2:1 (horizontal:vertical)
      class Logo < RSS::Element
        include CommonModel
        include URIContentModel

        def maker_target(target)
          target.maker.image
        end

        private
        def setup_maker_element_writer
          "url="
        end
      end

      # Atom Rights element
      #
      # TextConstruct that contains copyright information regarding the content in an Entry or Feed
      class Rights < RSS::Element
        include CommonModel
        include TextConstruct
      end

      # Atom Subtitle element
      #
      # TextConstruct that conveys a description or subtitle for a Feed
      class Subtitle < RSS::Element
        include CommonModel
        include TextConstruct
      end

      # Atom Title element
      #
      # TextConstruct that conveys a description or title for a feed or Entry
      class Title < RSS::Element
        include CommonModel
        include TextConstruct
      end

      # Atom Updated element
      #
      # DateConstruct indicating the most recent time when an Entry or Feed was modified
      # in a way the publisher considers significant
      class Updated < RSS::Element
        include CommonModel
        include DateConstruct
      end

      # Defines a child Atom Entry element for an Atom Feed
      class Entry < RSS::Element
        include CommonModel
        include DuplicateLinkChecker

        [
         ["author", "*", :children],
         ["category", "*", :children, "categories"],
         ["content", "?", :child],
         ["contributor", "*", :children],
         ["id", nil, nil, :content],
         ["link", "*", :children],
         ["published", "?", :child, :content],
         ["rights", "?", :child],
         ["source", "?"],
         ["summary", "?", :child],
         ["title", nil],
         ["updated", nil, :child, :content],
        ].each do |tag, occurs, type, *args|
          type ||= :attribute
          __send__("install_have_#{type}_element",
                   tag, URI, occurs, tag, *args)
        end

        # Returns whether any of the following are true
        # * There are any authors in the feed
        # * If the parent element has an author and the +check_parent+ parameter was given.
        # * There is a source element that has an author
        def have_author?(check_parent=true)
          authors.any? {|author| !author.to_s.empty?} or
            (check_parent and @parent and @parent.have_author?) or
            (source and source.have_author?)
        end

        private
        def atom_validate(ignore_unknown_element, tags, uri)
          unless have_author?
            raise MissingTagError.new("author", tag_name)
          end
          validate_duplicate_links(links)
        end

        def have_required_elements?
          super and have_author?
        end

        def maker_target(items)
          if items.respond_to?("items")
            # For backward compatibility
            items = items.items
          end
          items.new_item
        end

        Author = Feed::Author
        Category = Feed::Category

        class Content < RSS::Element
          include CommonModel

          class << self
            def xml_setter
              "xml="
            end

            def xml_getter
              "xml"
            end
          end

          [
           ["type", ""],
           ["src", "", false, [nil, :uri]],
          ].each do |name, uri, required, type|
            install_get_attribute(name, uri, required, type)
          end

          content_setup
          add_need_initialize_variable("xml")

          attr_writer :xml
          def have_xml_content?
            inline_xhtml? or inline_other_xml?
          end

          def xml
            return @xml unless inline_xhtml?
            return @xml if @xml.nil?
            if @xml.is_a?(XML::Element) and
                [@xml.name, @xml.uri] == ["div", XHTML_URI]
              return @xml
            end

            children = @xml
            children = [children] unless children.is_a?(Array)
            XML::Element.new("div", nil, XHTML_URI,
                             {"xmlns" => XHTML_URI}, children)
          end

          def xhtml
            if inline_xhtml?
              xml
            else
              nil
            end
          end

          def atom_validate(ignore_unknown_element, tags, uri)
            if out_of_line?
              raise MissingAttributeError.new(tag_name, "type") if @type.nil?
              unless (content.nil? or content.empty?)
                raise NotAvailableValueError.new(tag_name, content)
              end
            elsif inline_xhtml?
              if @xml.nil?
                raise MissingTagError.new("div", tag_name)
              end
              unless @xml.name == "div" and @xml.uri == XHTML_URI
                raise NotExpectedTagError.new(@xml.name, @xml.uri, tag_name)
              end
            end
          end

          def inline_text?
            !out_of_line? and [nil, "text", "html"].include?(@type)
          end

          def inline_html?
            return false if out_of_line?
            @type == "html" or mime_split == ["text", "html"]
          end

          def inline_xhtml?
            !out_of_line? and @type == "xhtml"
          end

          def inline_other?
            return false if out_of_line?
            media_type, subtype = mime_split
            return false if media_type.nil? or subtype.nil?
            true
          end

          def inline_other_text?
            return false unless inline_other?
            return false if inline_other_xml?

            media_type, = mime_split
            return true if "text" == media_type.downcase
            false
          end

          def inline_other_xml?
            return false unless inline_other?

            media_type, subtype = mime_split
            normalized_mime_type = "#{media_type}/#{subtype}".downcase
            if /(?:\+xml|^xml)$/ =~ subtype or
                %w(text/xml-external-parsed-entity
                   application/xml-external-parsed-entity
                   application/xml-dtd).find {|x| x == normalized_mime_type}
              return true
            end
            false
          end

          def inline_other_base64?
            inline_other? and !inline_other_text? and !inline_other_xml?
          end

          def out_of_line?
            not @src.nil?
          end

          def mime_split
            media_type = subtype = nil
            if /\A\s*([a-z]+)\/([a-z\+]+)\s*(?:;.*)?\z/i =~ @type.to_s
              media_type = $1.downcase
              subtype = $2.downcase
            end
            [media_type, subtype]
          end

          def need_base64_encode?
            inline_other_base64?
          end

          private
          def empty_content?
            out_of_line? or super
          end
        end

        Contributor = Feed::Contributor
        Id = Feed::Id
        Link = Feed::Link

        class Published < RSS::Element
          include CommonModel
          include DateConstruct
        end

        Rights = Feed::Rights

        class Source < RSS::Element
          include CommonModel

          [
           ["author", "*", :children],
           ["category", "*", :children, "categories"],
           ["contributor", "*", :children],
           ["generator", "?"],
           ["icon", "?"],
           ["id", "?", nil, :content],
           ["link", "*", :children],
           ["logo", "?"],
           ["rights", "?"],
           ["subtitle", "?"],
           ["title", "?"],
           ["updated", "?", nil, :content],
          ].each do |tag, occurs, type, *args|
            type ||= :attribute
            __send__("install_have_#{type}_element",
                     tag, URI, occurs, tag, *args)
          end

          def have_author?
            !author.to_s.empty?
          end

          Author = Feed::Author
          Category = Feed::Category
          Contributor = Feed::Contributor
          Generator = Feed::Generator
          Icon = Feed::Icon
          Id = Feed::Id
          Link = Feed::Link
          Logo = Feed::Logo
          Rights = Feed::Rights
          Subtitle = Feed::Subtitle
          Title = Feed::Title
          Updated = Feed::Updated
        end

        class Summary < RSS::Element
          include CommonModel
          include TextConstruct
        end

        Title = Feed::Title
        Updated = Feed::Updated
      end
    end

    # Defines a top-level Atom Entry element
    #
    class Entry < RSS::Element
      include RootElementMixin
      include CommonModel
      include DuplicateLinkChecker

      [
       ["author", "*", :children],
       ["category", "*", :children, "categories"],
       ["content", "?"],
       ["contributor", "*", :children],
       ["id", nil, nil, :content],
       ["link", "*", :children],
       ["published", "?", :child, :content],
       ["rights", "?"],
       ["source", "?"],
       ["summary", "?"],
       ["title", nil],
       ["updated", nil, nil, :content],
      ].each do |tag, occurs, type, *args|
        type ||= :attribute
        __send__("install_have_#{type}_element",
                 tag, URI, occurs, tag, *args)
      end

      # Creates a new Atom Entry element
      def initialize(version=nil, encoding=nil, standalone=nil)
        super("1.0", version, encoding, standalone)
        @feed_type = "atom"
        @feed_subtype = "entry"
      end

      # Returns the Entry in an array
      def items
        [self]
      end

      # sets up the +maker+ for constructing Entry elements
      def setup_maker(maker)
        maker = maker.maker if maker.respond_to?("maker")
        super(maker)
      end

      # Returns where there are any authors present or there is a source with an author
      def have_author?
        authors.any? {|author| !author.to_s.empty?} or
          (source and source.have_author?)
      end

      private
      def atom_validate(ignore_unknown_element, tags, uri)
        unless have_author?
          raise MissingTagError.new("author", tag_name)
        end
        validate_duplicate_links(links)
      end

      def have_required_elements?
        super and have_author?
      end

      def maker_target(maker)
        maker.items.new_item
      end

      Author = Feed::Entry::Author
      Category = Feed::Entry::Category
      Content = Feed::Entry::Content
      Contributor = Feed::Entry::Contributor
      Id = Feed::Entry::Id
      Link = Feed::Entry::Link
      Published = Feed::Entry::Published
      Rights = Feed::Entry::Rights
      Source = Feed::Entry::Source
      Summary = Feed::Entry::Summary
      Title = Feed::Entry::Title
      Updated = Feed::Entry::Updated
    end
  end

  Atom::CommonModel::ELEMENTS.each do |name|
    BaseListener.install_get_text_element(Atom::URI, name, "#{name}=")
  end

  module ListenerMixin
    private
    def initial_start_feed(tag_name, prefix, attrs, ns)
      check_ns(tag_name, prefix, ns, Atom::URI, false)

      @rss = Atom::Feed.new(@version, @encoding, @standalone)
      @rss.do_validate = @do_validate
      @rss.xml_stylesheets = @xml_stylesheets
      @rss.lang = attrs["xml:lang"]
      @rss.base = attrs["xml:base"]
      @last_element = @rss
      pr = Proc.new do |text, tags|
        @rss.validate_for_stream(tags) if @do_validate
      end
      @proc_stack.push(pr)
    end

    def initial_start_entry(tag_name, prefix, attrs, ns)
      check_ns(tag_name, prefix, ns, Atom::URI, false)

      @rss = Atom::Entry.new(@version, @encoding, @standalone)
      @rss.do_validate = @do_validate
      @rss.xml_stylesheets = @xml_stylesheets
      @rss.lang = attrs["xml:lang"]
      @rss.base = attrs["xml:base"]
      @last_element = @rss
      pr = Proc.new do |text, tags|
        @rss.validate_for_stream(tags) if @do_validate
      end
      @proc_stack.push(pr)
    end
  end
end
