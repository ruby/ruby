require "forwardable"

require "rss/rss"

module RSS

  class NotWellFormedError < Error
    attr_reader :line, :element
    def initialize(line=nil, element=nil)
      message = "This is not well formed XML"
      if element or line
        message << "\nerror occurred"
        message << " in #{element}" if element
        message << " at about #{line} line" if line
      end
      message << "\n#{yield}" if block_given?
      super(message)
    end
  end

  class XMLParserNotFound < Error
    def initialize
      super("available XML parser does not found in " <<
            "#{AVAILABLE_PARSER_LIBRARIES.inspect}.")
    end
  end

  class NotValidXMLParser < Error
    def initialize(parser)
      super("#{parser} is not available XML parser. " <<
            "available XML parser is " <<
            "#{AVAILABLE_PARSERS.inspect}.")
    end
  end

  class NSError < InvalidRSSError
    attr_reader :tag, :prefix, :uri
    def initialize(tag, prefix, require_uri)
      @tag, @prefix, @uri = tag, prefix, require_uri
      super("prefix <#{prefix}> doesn't associate uri " <<
            "<#{require_uri}> in tag <#{tag}>")
    end
  end

  class Parser

    extend Forwardable

    class << self

      @@default_parser = nil

      def default_parser
        @@default_parser || AVAILABLE_PARSERS.first
      end

      def default_parser=(new_value)
        if AVAILABLE_PARSERS.include?(new_value)
          @@default_parser = new_value
        else
          raise NotValidXMLParser.new(new_value)
        end
      end

      def parse(rss, do_validate=true, ignore_unknown_element=true, parser_class=default_parser)
        parser = new(rss, parser_class)
        parser.do_validate = do_validate
        parser.ignore_unknown_element = ignore_unknown_element
        parser.parse
      end

    end

    def_delegators(:@parser, :parse, :rss,
                   :ignore_unknown_element,
                   :ignore_unknown_element=, :do_validate,
                   :do_validate=)

    def initialize(rss, parser_class=self.class.default_parser)
      @parser = parser_class.new(rss)
    end
  end

  class BaseParser

    def initialize(rss)
      @listener = listener.new
      @rss = rss
    end

    def rss
      @listener.rss
    end

    def ignore_unknown_element
      @listener.ignore_unknown_element
    end

    def ignore_unknown_element=(new_value)
      @listener.ignore_unknown_element = new_value
    end

    def do_validate
      @listener.do_validate
    end

    def do_validate=(new_value)
      @listener.do_validate = new_value
    end

    def parse
      if @listener.rss.nil?
        _parse
      end
      @listener.rss
    end

  end

  class BaseListener

    extend Utils

    class << self

      @@setter = {}
      @@registered_uris = {}

      def install_setter(uri, tag_name, setter)
        @@setter[uri] = {}  unless @@setter.has_key?(uri)
        @@setter[uri][tag_name] = setter
      end

      def register_uri(name, uri)
        @@registered_uris[name] = {}  unless @@registered_uris.has_key?(name)
        @@registered_uris[name][uri] = nil
      end

      def uri_registered?(name, uri)
        @@registered_uris[name].has_key?(uri)
      end

      def setter(uri, tag_name)
        begin
          @@setter[uri][tag_name]
        rescue NameError
          nil
        end
      end

      def available_tags(uri)
        begin
          @@setter[uri].keys
        rescue NameError
          []
        end
      end
          
      def install_get_text_element(name, uri, setter)
        install_setter(uri, name, setter)
        def_get_text_element(uri, name, *get_file_and_line_from_caller(1))
      end
      
      private

      def def_get_text_element(uri, name, file, line)
        register_uri(name, uri)
        unless private_instance_methods(false).include?("start_#{name}")
          module_eval(<<-EOT, file, line)
          def start_#{name}(name, prefix, attrs, ns)
            uri = ns[prefix]
            if self.class.uri_registered?(#{name.inspect}, uri)
              if @do_validate
                tags = self.class.available_tags(uri)
                unless tags.include?(name)
                  raise UnknownTagError.new(name, uri)
                end
              end
              start_get_text_element(name, prefix, ns, uri)
            else
              start_else_element(name, prefix, attrs, ns)
            end
          end
          EOT
          send("private", "start_#{name}")
        end
      end

    end

  end

  module ListenerMixin

    attr_reader :rss

    attr_accessor :ignore_unknown_element
    attr_accessor :do_validate

    def initialize
      @rss = nil
      @ignore_unknown_element = true
      @do_validate = true
      @ns_stack = [{}]
      @tag_stack = [[]]
      @text_stack = ['']
      @proc_stack = []
      @last_element = nil
      @version = @encoding = @standalone = nil
      @xml_stylesheets = []
    end
    
    def xmldecl(version, encoding, standalone)
      @version, @encoding, @standalone = version, encoding, standalone
    end

    def instruction(name, content)
      if name == "xml-stylesheet"
        params = parse_pi_content(content)
        if params.has_key?("href")
          @xml_stylesheets << XMLStyleSheet.new(*params)
        end
      end
    end

    def tag_start(name, attributes)
      @text_stack.push('')

      ns = @ns_stack.last.dup
      attrs = {}
      attributes.each do |n, v|
        if n =~ /\Axmlns:?/
          ns[$POSTMATCH] = v
        else
          attrs[n] = v
        end
      end
      @ns_stack.push(ns)

      prefix, local = split_name(name)
      @tag_stack.last.push([ns[prefix], local])
      @tag_stack.push([])
      if respond_to?("start_#{local}", true)
        send("start_#{local}", local, prefix, attrs, ns.dup)
      else
        start_else_element(local, prefix, attrs, ns.dup)
      end
    end

    def tag_end(name)
      if DEBUG
        p "end tag #{name}"
        p @tag_stack
      end
      text = @text_stack.pop
      tags = @tag_stack.pop
      pr = @proc_stack.pop
      pr.call(text, tags) unless pr.nil?
    end

    def text(data)
      @text_stack.last << data
    end

    private

    CONTENT_PATTERN = /\s*([^=]+)=(["'])([^\2]+?)\2/
    def parse_pi_content(content)
      params = {}
      content.scan(CONTENT_PATTERN) do |name, quote, value|
        params[name] = value
      end
      params
    end

    def start_else_element(local, prefix, attrs, ns)
      class_name = local[0,1].upcase << local[1..-1]
      current_class = @last_element.class
#			begin
      if current_class.constants.include?(class_name)
        next_class = current_class.const_get(class_name)
        start_have_something_element(local, prefix, attrs, ns, next_class)
#			rescue NameError
      else
        if @ignore_unknown_element
          @proc_stack.push(nil)
        else
          parent = "ROOT ELEMENT???"
          if current_class.tag_name
            parent = current_class.tag_name
          end
          raise NotExceptedTagError.new(local, parent)
        end
      end
    end

    NAMESPLIT = /^(?:([\w:][-\w\d.]*):)?([\w:][-\w\d.]*)/
    def split_name(name)
      name =~ NAMESPLIT
      [$1 || '', $2]
    end

    def check_ns(tag_name, prefix, ns, require_uri)
      if @do_validate
        if ns[prefix] == require_uri
          #ns.delete(prefix)
        else
          raise NSError.new(tag_name, prefix, require_uri)
        end
      end
    end

    def start_get_text_element(tag_name, prefix, ns, required_uri)
      @proc_stack.push Proc.new {|text, tags|
        setter = self.class.setter(required_uri, tag_name)
        setter ||= "#{tag_name}="
        if @last_element.respond_to?(setter)
          @last_element.send(setter, text.to_s)
        else
          if @do_validate and not @ignore_unknown_element
            raise NotExceptedTagError.new(tag_name, @last_element.tag_name)
          end
        end
      }
    end

    def start_have_something_element(tag_name, prefix, attrs, ns, klass)

      check_ns(tag_name, prefix, ns, klass.required_uri)

      args = []
      
      klass.get_attributes.each do |a_name, a_uri, required|

        if a_uri.is_a?(String) or !a_uri.respond_to?(:include?)
          a_uri = [a_uri]
        end
        unless a_uri == [nil]
          for prefix, uri in ns
            if a_uri.include?(uri)
              val = attrs["#{prefix}:#{a_name}"]
              break if val
            end
          end
        end
        if val.nil? and a_uri.include?(nil)
          val = attrs[a_name]
        end

        if @do_validate and required and val.nil?
          unless a_uri.include?(nil)
            for prefix, uri in ns
              if a_uri.include?(uri)
                a_name = "#{prefix}:#{a_name}"
              end
            end
          end
          raise MissingAttributeError.new(tag_name, a_name)
        end

        args << val
      end

      previous = @last_element
      next_element = klass.send(:new, *args)
      next_element.do_validate = @do_validate
      prefix = ""
      prefix << "#{klass.required_prefix}_" if klass.required_prefix
      previous.__send__(:set_next_element, prefix, tag_name, next_element)
      @last_element = next_element
      @proc_stack.push Proc.new { |text, tags|
        p(@last_element.class) if DEBUG
        @last_element.content = text if klass.have_content?
        @last_element.validate_for_stream(tags) if @do_validate
        @last_element = previous
      }
    end

  end

  unless const_defined? :AVAILABLE_PARSER_LIBRARIES
    AVAILABLE_PARSER_LIBRARIES = [
      ["rss/xmlparser", :XMLParserParser],
      ["rss/xmlscanner", :XMLScanParser],
      ["rss/rexmlparser", :REXMLParser],
    ]
  end

  AVAILABLE_PARSERS = []

  AVAILABLE_PARSER_LIBRARIES.each do |lib, parser|
    begin
      require lib
      AVAILABLE_PARSERS.push(const_get(parser))
    rescue LoadError
    end
  end

  if AVAILABLE_PARSERS.empty?
    raise XMLParserNotFound
  end
end
