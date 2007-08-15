# XSD4R - XML QName definition.
# Copyright (C) 2002, 2003, 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


module XSD


class QName
  attr_accessor :namespace
  attr_accessor :name
  attr_accessor :source

  def initialize(namespace = nil, name = nil)
    @namespace = namespace
    @name = name
    @source = nil
  end

  def dup_name(name)
    XSD::QName.new(@namespace, name)
  end

  def dump
    ns = @namespace.nil? ? 'nil' : @namespace.dump
    name = @name.nil? ? 'nil' : @name.dump
    "XSD::QName.new(#{ns}, #{name})"
  end

  def match(rhs)
    if rhs.namespace and (rhs.namespace != @namespace)
      return false
    end
    if rhs.name and (rhs.name != @name)
      return false
    end
    true
  end

  def ==(rhs)
    !rhs.nil? and @namespace == rhs.namespace and @name == rhs.name
  end

  def ===(rhs)
    (self == rhs)
  end

  def eql?(rhs)
    (self == rhs)
  end

  def hash
    @namespace.hash ^ @name.hash
  end
  
  def to_s
    "{#{ namespace }}#{ name }"
  end

  def inspect
    sprintf("#<%s:0x%x %s>", self.class.name, __id__,
      "{#{ namespace }}#{ name }")
  end

  NormalizedNameRegexp = /^\{([^}]*)\}(.*)$/
  def parse(str)
    NormalizedNameRegexp =~ str
    self.new($1, $2)
  end

  EMPTY = QName.new.freeze
end


end
