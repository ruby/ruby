# Copyright (c) 2003-2004 Kouhei Sutou.  You can redistribute it and/or
# modify it under the same terms as Ruby.
#
# Author:: Kouhei Sutou <kou@cozmixng.org>
# Tutorial:: http://www.cozmixng.org/~rwiki/?cmd=view;name=RSS+Parser%3A%3ATutorial.en


require "time"

class Time
  class << self
    unless respond_to?(:w3cdtf)
      def w3cdtf(date)
        if /\A\s*
            (-?\d+)-(\d\d)-(\d\d)
            (?:T
            (\d\d):(\d\d)(?::(\d\d))?
            (\.\d+)?
            (Z|[+-]\d\d:\d\d)?)?
            \s*\z/ix =~ date and (($5 and $8) or (!$5 and !$8))
          datetime = [$1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i] 
          datetime << $7.to_f * 1000000 if $7
          if $8
            Time.utc(*datetime) - zone_offset($8)
          else
            Time.local(*datetime)
          end
        else
          raise ArgumentError.new("invalid date: #{date.inspect}")
        end
      end
    end
  end

  unless instance_methods.include?("w3cdtf")
    alias w3cdtf iso8601
  end
end

module Enumerable
  unless instance_methods.include?("sort_by")
    def sort_by
      collect do |x|
        [yield(x), x]
      end.sort do |x, y|
        x[0] <=> y[0]
      end.collect! do |x|
        x[1]
      end
    end
  end
end

require "English"
require "rss/utils"
require "rss/converter"
require "rss/xml-stylesheet"

module RSS

  VERSION = "0.1.2"

  URI = "http://purl.org/rss/1.0/"

  DEBUG = false

  class Error < StandardError; end

  class OverlappedPrefixError < Error
    attr_reader :prefix
    def initialize(prefix)
      @prefix = prefix
    end
  end

  class InvalidRSSError < Error; end

  class MissingTagError < InvalidRSSError
    attr_reader :tag, :parent
    def initialize(tag, parent)
      @tag, @parent = tag, parent
      super("tag <#{tag}> is missing in tag <#{parent}>")
    end
  end

  class TooMuchTagError < InvalidRSSError
    attr_reader :tag, :parent
    def initialize(tag, parent)
      @tag, @parent = tag, parent
      super("tag <#{tag}> is too much in tag <#{parent}>")
    end
  end

  class MissingAttributeError < InvalidRSSError
    attr_reader :tag, :attribute
    def initialize(tag, attribute)
      @tag, @attribute = tag, attribute
      super("attribute <#{attribute}> is missing in tag <#{tag}>")
    end
  end

  class UnknownTagError < InvalidRSSError
    attr_reader :tag, :uri
    def initialize(tag, uri)
      @tag, @uri = tag, uri
      super("tag <#{tag}> is unknown in namespace specified by uri <#{uri}>")
    end
  end

  class NotExceptedTagError < InvalidRSSError
    attr_reader :tag, :parent
    def initialize(tag, parent)
      @tag, @parent = tag, parent
      super("tag <#{tag}> is not expected in tag <#{parent}>")
    end
  end

  class NotAvailableValueError < InvalidRSSError
    attr_reader :tag, :value
    def initialize(tag, value)
      @tag, @value = tag, value
      super("value <#{value}> of tag <#{tag}> is not available.")
    end
  end

  class UnknownConversionMethodError < Error
    attr_reader :to, :from
    def initialize(to, from)
      @to = to
      @from = from
      super("can't convert to #{to} from #{from}.")
    end
  end
  # for backward compatibility
  UnknownConvertMethod = UnknownConversionMethodError

  class ConversionError < Error
    attr_reader :string, :to, :from
    def initialize(string, to, from)
      @string = string
      @to = to
      @from = from
      super("can't convert #{@string} to #{to} from #{from}.")
    end
  end

  class NotSetError < Error
    attr_reader :name, :variables
    def initialize(name, variables)
      @name = name
      @variables = variables
      super("required variables of #{@name} are not set: #{@variables.join(', ')}")
    end
  end
  
  module BaseModel

    include Utils

    def install_have_child_element(name)
      add_need_initialize_variable(name)

      attr_accessor name
      install_element(name) do |n, elem_name|
        <<-EOC
        if @#{n}
          "\#{@#{n}.to_s(convert, indent)}"
        else
          ''
        end
EOC
      end
    end
    alias_method(:install_have_attribute_element, :install_have_child_element)

    def install_have_children_element(name, plural_name=nil)
      plural_name ||= "#{name}s"
      add_have_children_element(name, plural_name)
      add_plural_form(name, plural_name)
      
      def_children_accessor(name, plural_name)
      install_element(name, "s") do |n, elem_name|
        <<-EOC
        rv = []
        @#{n}.each do |x|
          value = "\#{x.to_s(convert, indent)}"
          rv << value if /\\A\\s*\\z/ !~ value
        end
        rv.join("\n")
EOC
      end
    end

    def install_text_element(name)
      self::ELEMENTS << name
      add_need_initialize_variable(name)

      attr_writer name
      convert_attr_reader name
      install_element(name) do |n, elem_name|
        <<-EOC
        if @#{n}
          rv = "\#{indent}<#{elem_name}>"
          value = html_escape(@#{n})
          if convert and @converter
            rv << @converter.convert(value)
          else
            rv << value
          end
    	    rv << "</#{elem_name}>"
          rv
        else
          ''
        end
EOC
      end
    end

    def install_date_element(name, type, disp_name=name)
      self::ELEMENTS << name
      add_need_initialize_variable(name)

      # accessor
      convert_attr_reader name
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def #{name}=(new_value)
        if new_value.kind_of?(Time)
          @#{name} = new_value
        else
          if @do_validate
            begin
              @#{name} = Time.send('#{type}', new_value)
            rescue ArgumentError
              raise NotAvailableValueError.new('#{disp_name}', new_value)
            end
          else
            @#{name} = nil
            if /\\A\\s*\\z/ !~ new_value.to_s
              begin
                @#{name} = Time.parse(new_value)
              rescue ArgumentError
              end
            end
          end
        end

        # Is it need?
        if @#{name}
          class << @#{name}
            undef_method(:to_s)
            alias_method(:to_s, :#{type})
          end
        end

      end
EOC
      
      install_element(name) do |n, elem_name|
        <<-EOC
        if @#{n}
          rv = "\#{indent}<#{elem_name}>"
          value = html_escape(@#{n}.#{type})
          if convert and @converter
            rv << @converter.convert(value)
          else
            rv << value
          end
    	    rv << "</#{elem_name}>"
          rv
        else
          ''
        end
EOC
      end

    end

    private
    def install_element(name, postfix="")
      elem_name = name.sub('_', ':')
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def #{name}_element#{postfix}(convert=true, indent='')
        #{yield(name, elem_name)}
      end
      private :#{name}_element#{postfix}
EOC
    end

    def convert_attr_reader(*attrs)
      attrs.each do |attr|
        attr = attr.id2name if attr.kind_of?(Integer)
        module_eval(<<-EOC, *get_file_and_line_from_caller(2))
        def #{attr}
          if @converter
            @converter.convert(@#{attr})
          else
            @#{attr}
          end
        end
EOC
      end
    end

    def def_children_accessor(accessor_name, plural_name)
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def #{plural_name}
        @#{accessor_name}
      end

      def #{accessor_name}(*args)
        if args.empty?
          @#{accessor_name}.first
        else
          @#{accessor_name}.send("[]", *args)
        end
      end

      def #{accessor_name}=(*args)
        warn("Warning:\#{caller.first.sub(/:in `.*'\z/, '')}: " \
             "Don't use `#{accessor_name} = XXX'/`set_#{accessor_name}(XXX)'. " \
             "Those APIs are not sense of Ruby. " \
             "Use `#{plural_name} << XXX' instead of them.")
        if args.size == 1
          @#{accessor_name}.push(args[0])
        else
          @#{accessor_name}.send("[]=", *args)
        end
      end
      alias_method(:set_#{accessor_name}, :#{accessor_name}=)
EOC
    end

    def def_content_only_to_s
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def to_s(convert=true, indent=calc_indent)
        if @content
          rv = tag(indent) do |next_indent|
            h(@content)
          end
          rv = @converter.convert(rv) if convert and @converter
          rv
        else
          ""
        end
      end
EOC
    end
    
  end

  class Element

    extend BaseModel
    include Utils

    INDENT = "  "
    
    class << self

      def inherited(klass)
        klass.module_eval(<<-EOC)
        public
        
        @tag_name = name.split(/::/).last
        @tag_name[0,1] = @tag_name[0,1].downcase
        @indent_size = name.split(/::/).size - 2

        @@must_call_validators = {}

        def self.must_call_validators
          @@must_call_validators
        end

        def self.install_must_call_validator(prefix, uri)
          @@must_call_validators[uri] = prefix
        end
        
        @@model = []

        def self.model
          @@model
        end

        def self.install_model(tag, occurs=nil)
          if m = @@model.find {|t, o| t == tag}
            m[1] = occurs
          else
            @@model << [tag, occurs]
          end
        end

        @@get_attributes = []
        
        def self.get_attributes()
          @@get_attributes
        end

        def self.install_get_attribute(name, uri, required=true)
          attr_writer name
          convert_attr_reader name
          @@get_attributes << [name, uri, required]
        end

        @@have_content = false

        def self.content_setup
          attr_writer :content
          convert_attr_reader :content
          def_content_only_to_s
          @@have_content = true
        end

        def self.have_content?
          @@have_content
        end

        @@have_children_elements = []

        def self.have_children_elements
          @@have_children_elements
        end

        def self.add_have_children_element(variable_name, plural_name)
          @@have_children_elements << [variable_name, plural_name]
        end
        
        @@need_initialize_variables = []
        
        def self.add_need_initialize_variable(variable_name)
          @@need_initialize_variables << variable_name
        end
        
        def self.need_initialize_variables
          @@need_initialize_variables
        end

        @@plural_forms = {}
        
        def self.add_plural_form(singular, plural)
          @@plural_forms[singular] = plural
        end
        
        def self.plural_forms
          @@plural_forms
        end
        
        EOC
      end

      def required_prefix
        nil
      end

      def required_uri
        nil
      end
      
      def install_ns(prefix, uri)
        if self::NSPOOL.has_key?(prefix)
          raise OverlappedPrefixError.new(prefix)
        end
        self::NSPOOL[prefix] = uri
      end

      def tag_name
        @tag_name
      end
      
      def indent_size
        @indent_size
      end
      
    end

    attr_accessor :do_validate

    def initialize(do_validate=true)
      @converter = nil
      @do_validate = do_validate
      initialize_variables
    end

    def tag_name
      self.class.tag_name
    end

    def full_name
      tag_name
    end
    
    def indent_size
      self.class.indent_size
    end
    
    def converter=(converter)
      @converter = converter
      children.each do |child|
        child.converter = converter unless child.nil?
      end
    end
    
    def validate
      validate_attribute
      __validate
    end
    
    def validate_for_stream(tags)
      validate_attribute
      __validate(tags, false)
    end

    def setup_maker(maker)
      target = maker_target(maker)
      unless target.nil?
        setup_maker_attributes(target)
        setup_maker_element(target)
        setup_maker_elements(target)
      end
    end
    
    private
    def initialize_variables
      self.class.need_initialize_variables.each do |variable_name|
        instance_eval("@#{variable_name} = nil")
      end
      initialize_have_children_elements
      @content = "" if self.class.have_content?
    end

    def initialize_have_children_elements
      self.class.have_children_elements.each do |variable_name, plural_name|
        instance_eval("@#{variable_name} = []")
      end
    end

    def tag(indent, additional_attrs=[], &block)
      next_indent = indent + INDENT

      attrs = collect_attrs
      return "" if attrs.nil?

      attrs += additional_attrs
      start_tag = make_start_tag(indent, next_indent, attrs)

      if block
        content = block.call(next_indent)
      else
        content = []
      end

      if content.is_a?(String)
        content = [content]
        start_tag << ">"
        end_tag = "</#{full_name}>"
      else
        content = content.reject{|x| x.empty?}
        if content.empty?
          end_tag = "/>"
        else
          start_tag << ">\n"
          end_tag = "\n#{indent}</#{full_name}>"
        end
      end
      
      start_tag + content.join("\n") + end_tag
    end

    def make_start_tag(indent, next_indent, attrs)
      start_tag = ["#{indent}<#{full_name}"]
      unless attrs.empty?
        start_tag << attrs.collect do |key, value|
          %Q[#{h key}="#{h value}"]
        end.join("\n#{next_indent}")
      end
      start_tag.join(" ")
    end

    def collect_attrs
      _attrs.collect do |name, required, alias_name|
        value = __send__(alias_name || name)
        return nil if required and value.nil?
        [name, value]
      end.reject do |name, value|
        value.nil?
      end
    end
    
    def tag_name_with_prefix(prefix)
      "#{prefix}:#{tag_name}"
    end
    
    def calc_indent
      INDENT * (self.class.indent_size)
    end

    def maker_target(maker)
      nil
    end
    
    def setup_maker_attributes(target)
    end
    
    def setup_maker_element(target)
      self.class.need_initialize_variables.each do |var|
        setter = "#{var}="
        if target.respond_to?(setter)
          target.__send__(setter, __send__(var))
        end
      end
    end
    
    def setup_maker_elements(parent)
      self.class.have_children_elements.each do |name, plural_name|
        real_name = name.sub(/^[^_]+_/, '')
        if parent.respond_to?(plural_name)
          target = parent.__send__(plural_name)
          __send__(plural_name).each do |elem|
            elem.__send__("setup_maker", target)
          end
        end
      end
    end

    def set_next_element(prefix, tag_name, next_element)
      klass = next_element.class
      prefix = ""
      prefix << "#{klass.required_prefix}_" if klass.required_prefix
      if self.class.plural_forms.has_key?(tag_name)
        ary = __send__("#{prefix}#{self.class.plural_forms[tag_name]}")
        ary << next_element
      else
        __send__("#{prefix}#{tag_name}=", next_element)
      end
    end
    
    # not String class children.
    def children
      []
    end

    # default #validate() argument.
    def _tags
      []
    end

    def _attrs
      []
    end

    def __validate(tags=_tags, recursive=true)
      if recursive
        children.compact.each do |child|
          child.validate
        end
      end
      must_call_validators = self.class.must_call_validators
      tags = tag_filter(tags.dup)
      p tags if DEBUG
      self.class::NSPOOL.each do |prefix, uri|
        if tags.has_key?(uri) and !must_call_validators.has_key?(uri)
          meth = "#{prefix}_validate"
          send(meth, tags[uri]) if respond_to?(meth, true)
        end
      end
      must_call_validators.each do |uri, prefix|
        send("#{prefix}_validate", tags[uri])
      end
    end

    def validate_attribute
      _attrs.each do |a_name, required, alias_name|
        if required and __send__(alias_name || a_name).nil?
          raise MissingAttributeError.new(tag_name, a_name)
        end
      end
    end

    def other_element(convert, indent='')
      rv = []
      private_methods.each do |meth|
        if /\A([^_]+)_[^_]+_elements?\z/ =~ meth and
            self.class::NSPOOL.has_key?($1)
          res = __send__(meth, convert)
          rv << "#{indent}#{res}" if /\A\s*\z/ !~ res
        end
      end
      rv.join("\n")
    end

    def _validate(tags, model=self.class.model)
      count = 1
      do_redo = false
      not_shift = false
      tag = nil
      element_names = model.collect {|elem| elem[0]}
      if tags
        tags_size = tags.size
        tags = tags.sort_by {|x| element_names.index(x) || tags_size}
      end

      model.each_with_index do |elem, i|

        if DEBUG
          p "before" 
          p tags
          p elem
        end

        if not_shift
          not_shift = false
        elsif tags
          tag = tags.shift
        end

        if DEBUG
          p "mid"
          p count
        end

        case elem[1]
        when '?'
          if count > 2
            raise TooMuchTagError.new(elem[0], tag_name)
          else
            if elem[0] == tag
              do_redo = true
            else
              not_shift = true
            end
          end
        when '*'
          if elem[0] == tag
            do_redo = true
          else
            not_shift = true
          end
        when '+'
          if elem[0] == tag
            do_redo = true
          else
            if count > 1
              not_shift = true
            else
              raise MissingTagError.new(elem[0], tag_name)
            end
          end
        else
          if elem[0] == tag
            if model[i+1] and model[i+1][0] != elem[0] and
                tags and tags.first == elem[0]
              raise TooMuchTagError.new(elem[0], tag_name)
            end
          else
            raise MissingTagError.new(elem[0], tag_name)
          end
        end

        if DEBUG
          p "after"
          p not_shift
          p do_redo
          p tag
        end

        if do_redo
          do_redo = false
          count += 1
          redo
        else
          count = 1
        end

      end

      if !tags.nil? and !tags.empty?
        raise NotExceptedTagError.new(tag, tag_name)
      end

    end

    def tag_filter(tags)
      rv = {}
      tags.each do |tag|
        rv[tag[0]] = [] unless rv.has_key?(tag[0])
        rv[tag[0]].push(tag[1])
      end
      rv
    end

  end

  module RootElementMixin

    include XMLStyleSheetMixin
    
    attr_reader :output_encoding

    def initialize(rss_version, version=nil, encoding=nil, standalone=nil)
      super()
      @rss_version = rss_version
      @version = version || '1.0'
      @encoding = encoding
      @standalone = standalone
      @output_encoding = nil
    end

    def output_encoding=(enc)
      @output_encoding = enc
      self.converter = Converter.new(@output_encoding, @encoding)
    end

    def setup_maker(maker)
      maker.version = version
      maker.encoding = encoding
      maker.standalone = standalone

      xml_stylesheets.each do |xss|
        xss.setup_maker(maker)
      end

      setup_maker_elements(maker)
    end
    
    private
    def tag(indent, attrs, &block)
      rv = xmldecl + xml_stylesheet_pi
      rv << super(indent, attrs, &block)
      rv
    end

    def xmldecl
      rv = %Q[<?xml version="#{@version}"]
      if @output_encoding or @encoding
        rv << %Q[ encoding="#{@output_encoding or @encoding}"]
      end
      rv << %Q[ standalone="yes"] if @standalone
      rv << "?>\n"
      rv
    end
    
    def ns_declarations
      self.class::NSPOOL.collect do |prefix, uri|
        prefix = ":#{prefix}" unless prefix.empty?
        ["xmlns#{prefix}", uri]
      end
    end
    
    def setup_maker_elements(maker)
      channel.setup_maker(maker) if channel
      image.setup_maker(maker) if image
      textinput.setup_maker(maker) if textinput
      items.each do |item|
        item.setup_maker(maker)
      end
    end
  end

end
