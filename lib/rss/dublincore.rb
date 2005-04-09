require "rss/1.0"

module RSS

  DC_PREFIX = 'dc'
  DC_URI = "http://purl.org/dc/elements/1.1/"
  
  RDF.install_ns(DC_PREFIX, DC_URI)

  module BaseDublinCoreModel
    def append_features(klass)
      super

      return if klass.instance_of?(Module)
      DublinCoreModel::ELEMENT_NAME_INFOS.each do |name, plural_name|
        plural = plural_name || "#{name}s"
        full_name = "#{DC_PREFIX}_#{name}"
        full_plural_name = "#{DC_PREFIX}_#{plural}"
        klass_name = "DublinCore#{Utils.to_class_name(name)}"
        klass.module_eval(<<-EOC, *get_file_and_line_from_caller(0))
          install_have_children_element(#{full_name.dump},
                                        #{full_plural_name.dump})

          remove_method :#{full_name}
          remove_method :#{full_name}=
          remove_method :set_#{full_name}

          def #{full_name}
            @#{full_name}.first and @#{full_name}.first.value
          end
          
          def #{full_name}=(new_value)
            @#{full_name}[0] = Utils.new_with_value_if_need(#{klass_name}, new_value)
          end
          alias set_#{full_name} #{full_name}=
        EOC
      end
      klass.module_eval(<<-EOC, *get_file_and_line_from_caller(0))
        alias date #{DC_PREFIX}_date
        alias date= #{DC_PREFIX}_date=
      EOC
    end
  end
  
  module DublinCoreModel

    extend BaseModel
    extend BaseDublinCoreModel

    TEXT_ELEMENTS = {
      "title" => nil,
      "description" => nil,
      "creator" => nil,
      "subject" => nil,
      "publisher" => nil,
      "contributor" => nil,
      "type" => nil,
      "format" => nil,
      "identifier" => nil,
      "source" => nil,
      "language" => nil,
      "relation" => nil,
      "coverage" => nil,
      "rights" => "rightses" # FIXME
    }

    DATE_ELEMENTS = {
      "date" => "w3cdtf",
    }
    
    ELEMENT_NAME_INFOS = DublinCoreModel::TEXT_ELEMENTS.to_a
    DublinCoreModel::DATE_ELEMENTS.each do |name, |
      ELEMENT_NAME_INFOS << [name, nil]
    end
    
    ELEMENTS = TEXT_ELEMENTS.keys + DATE_ELEMENTS.keys

    ELEMENTS.each do |name, plural_name|
      module_eval(<<-EOC, *get_file_and_line_from_caller(0))
        class DublinCore#{Utils.to_class_name(name)} < Element
          include RSS10
          
          content_setup

          class << self
            def required_prefix
              DC_PREFIX
            end
        
            def required_uri
              DC_URI
            end
          end

          @tag_name = #{name.dump}

          alias_method(:value, :content)
          alias_method(:value=, :content=)
          
          def initialize(content=nil)
            super()
            self.content = content
          end
      
          def full_name
            tag_name_with_prefix(DC_PREFIX)
          end

          def maker_target(target)
            target.new_#{name}
          end

          def setup_maker_attributes(#{name})
            #{name}.content = content
          end
        end
      EOC
    end

    DATE_ELEMENTS.each do |name, type|
      module_eval(<<-EOC, *get_file_and_line_from_caller(0))
        class DublinCore#{Utils.to_class_name(name)} < Element
          remove_method(:content=)
          remove_method(:value=)

          date_writer("content", #{type.dump}, #{name.dump})
          
          alias_method(:value=, :content=)
        end
      EOC
    end
      
    def dc_validate(tags)
      tags.each do |tag|
        key = "#{DC_PREFIX}_#{tag}"
        unless DublinCoreModel::ELEMENTS.include?(key)
          raise UnknownTagError.new(tag, DC_URI)
        end
      end
    end

  end

  # For backward compatibility
  DublincoreModel = DublinCoreModel

  class RDF
    class Channel; include DublinCoreModel; end
    class Image; include DublinCoreModel; end
    class Item; include DublinCoreModel; end
    class Textinput; include DublinCoreModel; end
  end

  DublinCoreModel::ELEMENTS.each do |name|
    class_name = Utils.to_class_name(name)
    BaseListener.install_class_name(DC_URI, name, "DublinCore#{class_name}")
  end

  DublinCoreModel::ELEMENTS.collect! {|name| "#{DC_PREFIX}_#{name}"}
end
