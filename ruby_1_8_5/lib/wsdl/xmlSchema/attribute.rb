# WSDL4R - XMLSchema attribute definition for WSDL.
# Copyright (C) 2002, 2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL
module XMLSchema


class Attribute < Info
  class << self
    if RUBY_VERSION > "1.7.0"
      def attr_reader_ref(symbol)
        name = symbol.to_s
        define_method(name) {
          instance_variable_get("@#{name}") ||
            (refelement ? refelement.__send__(name) : nil)
        }
      end
    else
      def attr_reader_ref(symbol)
        name = symbol.to_s
        module_eval <<-EOS
          def #{name}
            @#{name} || (refelement ? refelement.#{name} : nil)
          end
        EOS
      end
    end
  end

  attr_writer :use
  attr_writer :form
  attr_writer :name
  attr_writer :type
  attr_writer :local_simpletype
  attr_writer :default
  attr_writer :fixed

  attr_reader_ref :use
  attr_reader_ref :form
  attr_reader_ref :name
  attr_reader_ref :type
  attr_reader_ref :local_simpletype
  attr_reader_ref :default
  attr_reader_ref :fixed

  attr_accessor :ref
  attr_accessor :arytype

  def initialize
    super
    @use = nil
    @form = nil
    @name = nil
    @type = nil
    @local_simpletype = nil
    @default = nil
    @fixed = nil
    @ref = nil
    @refelement = nil
    @arytype = nil
  end

  def refelement
    @refelement ||= root.collect_attributes[@ref]
  end

  def targetnamespace
    parent.targetnamespace
  end

  def parse_element(element)
    case element
    when SimpleTypeName
      @local_simpletype = SimpleType.new
      @local_simpletype
    end
  end

  def parse_attr(attr, value)
    case attr
    when RefAttrName
      @ref = value
    when UseAttrName
      @use = value.source
    when FormAttrName
      @form = value.source
    when NameAttrName
      if directelement?
        @name = XSD::QName.new(targetnamespace, value.source)
      else
        @name = XSD::QName.new(nil, value.source)
      end
    when TypeAttrName
      @type = value
    when DefaultAttrName
      @default = value.source
    when FixedAttrName
      @fixed = value.source
    when ArrayTypeAttrName
      @arytype = if value.namespace.nil?
          XSD::QName.new(XSD::Namespace, value.source)
        else
          value
        end
    else
      nil
    end
  end

private

  def directelement?
    parent.is_a?(Schema)
  end
end


end
end
