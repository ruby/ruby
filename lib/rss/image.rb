require 'rss/1.0'
require 'rss/dublincore'

module RSS

  IMAGE_PREFIX = 'image'
  IMAGE_URI = 'http://web.resource.org/rss/1.0/modules/image/'

  RDF.install_ns(IMAGE_PREFIX, IMAGE_URI)

  module ImageModelUtils
    def validate_one_tag_name(name, tags)
      invalid = tags.find {|tag| tag != name}
      raise UnknownTagError.new(invalid, IMAGE_URI) if invalid
      raise TooMuchTagError.new(name, tag_name) if tags.size > 1
    end
  end
  
  module ImageItemModel
    include ImageModelUtils
    extend BaseModel

    def self.append_features(klass)
      super

      klass.install_have_child_element("#{IMAGE_PREFIX}_item")
    end

    def image_validate(tags)
      validate_one_tag_name("item", tags)
    end
    
    class Item < Element
      include RSS10
      include DublinCoreModel

      class << self
        def required_prefix
          IMAGE_PREFIX
        end
        
        def required_uri
          IMAGE_URI
        end
      end
      
      [
        ["about", ::RSS::RDF::URI, true],
        ["resource", ::RSS::RDF::URI, false],
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end

      %w(width height).each do |tag|
        full_name = "#{IMAGE_PREFIX}_#{tag}"
        install_text_element(full_name)
        BaseListener.install_get_text_element(IMAGE_URI, tag, "#{full_name}=")
      end

      def initialize(about=nil, resource=nil)
        super()
        @about = about
        @resource = resource
      end

      def full_name
        tag_name_with_prefix(IMAGE_PREFIX)
      end
      
      def to_s(need_convert=true, indent=calc_indent)
        rv = tag(indent) do |next_indent|
          [
            other_element(false, next_indent),
          ]
        end
        rv = convert(rv) if need_convert
        rv
      end

      alias _image_width= image_width=
      def image_width=(new_value)
        if @do_validate
          self._image_width = Integer(new_value)
        else
          self._image_width = new_value.to_i
        end
      end

      alias _image_height= image_height=
      def image_height=(new_value)
        if @do_validate
          self._image_height = Integer(new_value)
        else
          self._image_height = new_value.to_i
        end
      end

      alias width= image_width=
      alias width image_width
      alias height= image_height=
      alias height image_height

      private
      def _tags
        [
          [IMAGE_URI, 'width'],
          [IMAGE_URI, 'height'],
        ].delete_if do |uri, name|
          send(name).nil?
        end
      end
        
      def _attrs
        [
          ["#{::RSS::RDF::PREFIX}:about", true, "about"],
          ["#{::RSS::RDF::PREFIX}:resource", false, "resource"],
        ]
      end

      def maker_target(target)
        target.image_item
      end

      def setup_maker_attributes(item)
        item.about = self.about
        item.resource = self.resource
      end
    end
  end
  
  module ImageFaviconModel
    include ImageModelUtils
    extend BaseModel
    
    def self.append_features(klass)
      super

      unless klass.class == Module
        klass.install_have_child_element("#{IMAGE_PREFIX}_favicon")
      end
    end

    def image_validate(tags)
      validate_one_tag_name("favicon", tags)
    end
    
    class Favicon < Element
      include RSS10
      include DublinCoreModel

      class << self
        def required_prefix
          IMAGE_PREFIX
        end
        
        def required_uri
          IMAGE_URI
        end
      end
      
      [
        ["about", ::RSS::RDF::URI, true],
        ["size", IMAGE_URI, true],
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end

      alias image_size= size=
      alias image_size size

      def initialize(about=nil, size=nil)
        super()
        @about = about
        @size = size
      end

      def full_name
        tag_name_with_prefix(IMAGE_PREFIX)
      end
      
      def to_s(need_convert=true, indent=calc_indent)
        rv = tag(indent) do |next_indent|
          [
            other_element(false, next_indent),
          ]
        end
        rv = convert(rv) if need_convert
        rv
      end

      private
      def _attrs
        [
          ["#{::RSS::RDF::PREFIX}:about", true, "about"],
          ["#{IMAGE_PREFIX}:size", true, "size"],
        ]
      end

      def maker_target(target)
        target.image_favicon
      end

      def setup_maker_attributes(favicon)
        favicon.about = self.about
        favicon.size = self.size
      end
    end

  end

  class RDF
    class Channel; include ImageFaviconModel; end
    class Item; include ImageItemModel; end
  end

end
