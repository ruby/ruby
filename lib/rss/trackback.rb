require 'rss/1.0'
require 'rss/2.0'

module RSS

  TRACKBACK_PREFIX = 'trackback'
  TRACKBACK_URI = 'http://madskills.com/public/xml/rss/module/trackback/'

  RDF.install_ns(TRACKBACK_PREFIX, TRACKBACK_URI)
  Rss.install_ns(TRACKBACK_PREFIX, TRACKBACK_URI)

  module TrackBackUtils
    private
    def new_with_value_if_need(klass, value)
      if value.is_a?(klass)
        value
      else
        klass.new(value)
      end
    end
          
    def trackback_validate(tags)
      counter = {}
      %w(ping about).each do |x|
        counter["#{TRACKBACK_PREFIX}_#{x}"] = 0
      end

      tags.each do |tag|
        key = "#{TRACKBACK_PREFIX}_#{tag}"
        raise UnknownTagError.new(tag, TRACKBACK_URI) unless counter.has_key?(key)
        counter[key] += 1
        if tag != "about" and counter[key] > 1
          raise TooMuchTagError.new(tag, tag_name)
        end
      end

      if counter["#{TRACKBACK_PREFIX}_ping"].zero? and
          counter["#{TRACKBACK_PREFIX}_about"].nonzero?
        raise MissingTagError.new("#{TRACKBACK_PREFIX}:ping", tag_name)
      end
    end
  end
  
  module BaseTrackBackModel
    def append_features(klass)
      super

      unless klass.class == Module
        klass.__send__(:include, TrackBackUtils)

        %w(ping).each do |x|
          var_name = "#{TRACKBACK_PREFIX}_#{x}"
          klass_name = x.capitalize
          klass.install_have_child_element(var_name)
          klass.module_eval(<<-EOC, __FILE__, __LINE__)
            remove_method :#{var_name}
            def #{var_name}
              @#{var_name} and @#{var_name}.value
            end

            remove_method :#{var_name}=
            def #{var_name}=(value)
              @#{var_name} = new_with_value_if_need(#{klass_name}, value)
            end
          EOC
        end
        
        [%w(about s)].each do |name, postfix|
          var_name = "#{TRACKBACK_PREFIX}_#{name}"
          klass_name = name.capitalize
          klass.install_have_children_element(var_name)
          klass.module_eval(<<-EOC, __FILE__, __LINE__)
            remove_method :#{var_name}
            def #{var_name}(*args)
              if args.empty?
                @#{var_name}.first and @#{var_name}.first.value
              else
                ret = @#{var_name}.send("[]", *args)
                if ret.is_a?(Array)
                  ret.collect {|x| x.value}
                else
                  ret.value
                end
              end
            end

            remove_method :#{var_name}=
            remove_method :set_#{var_name}
            def #{var_name}=(*args)
              if args.size == 1
                item = new_with_value_if_need(#{klass_name}, args[0])
                @#{var_name}.push(item)
              else
                new_val = args.last
                if new_val.is_a?(Array)
                  new_val = new_value.collect do |val|
                    new_with_value_if_need(#{klass_name}, val)
                  end
                else
                  new_val = new_with_value_if_need(#{klass_name}, new_val)
                end
                @#{var_name}.send("[]=", *(args[0..-2] + [new_val]))
              end
            end
            alias set_#{var_name} #{var_name}=
          EOC
        end
      end
    end
  end

  module TrackBackModel10
    extend BaseModel
    extend BaseTrackBackModel

    class Ping < Element
      include RSS10

      class << self

        def required_prefix
          TRACKBACK_PREFIX
        end
        
        def required_uri
          TRACKBACK_URI
        end

      end
      
      [
        ["resource", ::RSS::RDF::URI, true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end

      alias_method(:value, :resource)
      alias_method(:value=, :resource=)
      
      def initialize(resource=nil)
        super()
        @resource = resource
      end

      def full_name
        tag_name_with_prefix(TRACKBACK_PREFIX)
      end
      
      def to_s(convert=true, indent=calc_indent)
        rv = tag(indent)
        rv = @converter.convert(rv) if convert and @converter
        rv
      end

      private
      def _attrs
        [
          ["#{::RSS::RDF::PREFIX}:resource", true, "resource"],
        ]
      end

    end

    class About < Element
      include RSS10

      class << self
        
        def required_prefix
          TRACKBACK_PREFIX
        end
        
        def required_uri
          TRACKBACK_URI
        end

      end
      
      [
        ["resource", ::RSS::RDF::URI, true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end

      alias_method(:value, :resource)
      alias_method(:value=, :resource=)
      
      def initialize(resource=nil)
        super()
        @resource = resource
      end

      def full_name
        tag_name_with_prefix(TRACKBACK_PREFIX)
      end
      
      def to_s(convert=true, indent=calc_indent)
        rv = tag(indent)
        rv = @converter.convert(rv) if convert and @converter
        rv
      end

      private
      def _attrs
        [
          ["#{::RSS::RDF::PREFIX}:resource", true, "resource"],
        ]
      end

      def maker_target(abouts)
        abouts.new_about
      end

      def setup_maker_attributes(about)
        about.resource = self.resource
      end
      
    end
  end

  module TrackBackModel20
    extend BaseModel
    extend BaseTrackBackModel

    class Ping < Element
      include RSS09

      content_setup

      class << self

        def required_prefix
          TRACKBACK_PREFIX
        end
        
        def required_uri
          TRACKBACK_URI
        end

      end
      
      alias_method(:value, :content)
      alias_method(:value=, :content=)

      def initialize(content=nil)
        super()
        @content = content
      end
      
      def full_name
        tag_name_with_prefix(TRACKBACK_PREFIX)
      end
      
    end

    class About < Element
      include RSS09

      content_setup

      class << self
        
        def required_prefix
          TRACKBACK_PREFIX
        end
        
        def required_uri
          TRACKBACK_URI
        end

      end

      alias_method(:value, :content)
      alias_method(:value=, :content=)

      def initialize(content=nil)
        super()
        @content = content
      end
      
      def full_name
        tag_name_with_prefix(TRACKBACK_PREFIX)
      end
      
    end
  end

  class RDF
    class Item; include TrackBackModel10; end
  end

  class Rss
    class Channel
      class Item; include TrackBackModel20; end
    end
  end

end
