# XSD4R - Generating class definition code
# Copyright (C) 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/codegen/gensupport'
require 'xsd/codegen/moduledef'
require 'xsd/codegen/methoddef'


module XSD
module CodeGen


class ClassDef < ModuleDef
  include GenSupport

  def initialize(name, baseclass = nil)
    super(name)
    @baseclass = baseclass
    @classvar = []
    @attrdef = []
  end

  def def_classvar(var, value)
    var = var.sub(/\A@@/, "")
    unless safevarname?(var)
      raise ArgumentError.new("#{var} seems to be unsafe")
    end
    @classvar << [var, value]
  end

  def def_attr(attrname, writable = true, varname = nil)
    unless safevarname?(varname || attrname)
      raise ArgumentError.new("#{varname || attrname} seems to be unsafe")
    end
    @attrdef << [attrname, writable, varname]
  end

  def dump
    buf = ""
    unless @requirepath.empty?
      buf << dump_requirepath
    end
    buf << dump_emptyline unless buf.empty?
    package = @name.split(/::/)[0..-2]
    buf << dump_package_def(package) unless package.empty?
    buf << dump_comment if @comment
    buf << dump_class_def
    spacer = false
    unless @classvar.empty?
      spacer = true
      buf << dump_classvar
    end
    unless @const.empty?
      buf << dump_emptyline if spacer
      spacer = true
      buf << dump_const
    end
    unless @code.empty?
      buf << dump_emptyline if spacer
      spacer = true
      buf << dump_code
    end
    unless @attrdef.empty?
      buf << dump_emptyline if spacer
      spacer = true
      buf << dump_attributes
    end
    unless @methoddef.empty?
      buf << dump_emptyline if spacer
      spacer = true
      buf << dump_methods
    end
    buf << dump_class_def_end
    buf << dump_package_def_end(package) unless package.empty?
    buf.gsub(/^\s+$/, '')
  end

private

  def dump_class_def
    name = @name.to_s.split(/::/)
    if @baseclass
      format("class #{name.last} < #{@baseclass}")
    else
      format("class #{name.last}")
    end
  end

  def dump_class_def_end
    str = format("end")
  end

  def dump_classvar
    dump_static(
      @classvar.collect { |var, value|
        %Q(@@#{var.sub(/^@@/, "")} = #{dump_value(value)})
      }.join("\n")
    )
  end

  def dump_attributes
    str = ""
    @attrdef.each do |attrname, writable, varname|
      varname ||= attrname
      if attrname == varname
        str << format(dump_accessor(attrname, writable), 2)
      end
    end
    @attrdef.each do |attrname, writable, varname|
      varname ||= attrname
      if attrname != varname
        str << "\n" unless str.empty?
        str << format(dump_attribute(attrname, writable, varname), 2)
      end
    end
    str
  end

  def dump_accessor(attrname, writable)
    if writable
      "attr_accessor :#{attrname}"
    else
      "attr_reader :#{attrname}"
    end
  end

  def dump_attribute(attrname, writable, varname)
    str = nil
    mr = MethodDef.new(attrname)
    mr.definition = "@#{varname}"
    str = mr.dump
    if writable
      mw = MethodDef.new(attrname + "=", 'value')
      mw.definition = "@#{varname} = value"
      str << "\n" + mw.dump
    end
    str
  end
end


end
end


if __FILE__ == $0
  require 'xsd/codegen/classdef'
  include XSD::CodeGen
  c = ClassDef.new("Foo::Bar::HobbitName", String)
  c.def_require("foo/bar")
  c.comment = <<-EOD
      foo
    bar
      baz
  EOD
  c.def_const("FOO", 1)
  c.def_classvar("@@foo", "var".dump)
  c.def_classvar("baz", "1".dump)
  c.def_attr("Foo", true, "foo")
  c.def_attr("bar")
  c.def_attr("baz", true)
  c.def_attr("Foo2", true, "foo2")
  c.def_attr("foo3", false, "foo3")
  c.def_method("foo") do
    <<-EOD
        foo.bar = 1
\tbaz.each do |ele|
\t  ele
        end
    EOD
  end
  c.def_method("baz", "qux") do
    <<-EOD
      [1, 2, 3].each do |i|
        p i
      end
    EOD
  end

  m = MethodDef.new("qux", "quxx", "quxxx") do
    <<-EOD
    p quxx + quxxx
    EOD
  end
  m.comment = "hello world\n123"
  c.add_method(m)
  c.def_code <<-EOD
    Foo.new
    Bar.z
  EOD
  c.def_code <<-EOD
    Foo.new
    Bar.z
  EOD
  c.def_privatemethod("foo", "baz", "*arg", "&block")

  puts c.dump
end
