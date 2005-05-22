# XSD4R - Generating module definition code
# Copyright (C) 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/codegen/gensupport'
require 'xsd/codegen/methoddef'
require 'xsd/codegen/commentdef'


module XSD
module CodeGen


class ModuleDef
  include GenSupport
  include CommentDef

  def initialize(name)
    @name = name
    @comment = nil
    @const = []
    @code = []
    @requirepath = []
    @methoddef = []
  end

  def def_require(path)
    @requirepath << path
  end

  def def_const(const, value)
    unless safeconstname?(const)
      raise ArgumentError.new("#{const} seems to be unsafe")
    end
    @const << [const, value]
  end

  def def_code(code)
    @code << code
  end

  def def_method(name, *params)
    add_method(MethodDef.new(name, *params) { yield if block_given? }, :public)
  end
  alias def_publicmethod def_method

  def def_protectedmethod(name, *params)
    add_method(MethodDef.new(name, *params) { yield if block_given? },
      :protected)
  end

  def def_privatemethod(name, *params)
    add_method(MethodDef.new(name, *params) { yield if block_given? }, :private)
  end

  def add_method(m, visibility = :public)
    @methoddef << [visibility, m]
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
    buf << dump_module_def
    spacer = false
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
    unless @methoddef.empty?
      buf << dump_emptyline if spacer
      spacer = true
      buf << dump_methods
    end
    buf << dump_module_def_end
    buf << dump_package_def_end(package) unless package.empty?
    buf.gsub(/^\s+$/, '')
  end

private

  def dump_requirepath
    format(
      @requirepath.collect { |path|
        %Q(require '#{path}')
      }.join("\n")
    )
  end

  def dump_const
    dump_static(
      @const.sort.collect { |var, value|
        %Q(#{var} = #{dump_value(value)})
      }.join("\n")
    )
  end

  def dump_code
    dump_static(@code.join("\n"))
  end

  def dump_static(str)
    format(str, 2)
  end

  def dump_methods
    methods = {}
    @methoddef.each do |visibility, method|
      (methods[visibility] ||= []) << method
    end
    str = ""
    [:public, :protected, :private].each do |visibility|
      if methods[visibility]
        str << "\n" unless str.empty?
        str << visibility.to_s << "\n\n" unless visibility == :public
        str << methods[visibility].collect { |m| format(m.dump, 2) }.join("\n")
      end
    end
    str
  end

  def dump_value(value)
    if value.respond_to?(:to_src)
      value.to_src
    else
      value
    end
  end

  def dump_package_def(package)
    format(package.collect { |ele| "module #{ele}" }.join("; ")) + "\n\n"
  end

  def dump_package_def_end(package)
    "\n\n" + format(package.collect { |ele| "end" }.join("; "))
  end

  def dump_module_def
    name = @name.to_s.split(/::/)
    format("module #{name.last}")
  end

  def dump_module_def_end
    format("end")
  end
end


end
end


if __FILE__ == $0
  require 'xsd/codegen/moduledef'
  include XSD::CodeGen
  m = ModuleDef.new("Foo::Bar::HobbitName")
  m.def_require("foo/bar")
  m.def_require("baz")
  m.comment = <<-EOD
    foo
    bar
    baz
  EOD
  m.def_method("foo") do
    <<-EOD
      foo.bar = 1
      baz.each do |ele|
        ele + 1
      end
    EOD
  end
  m.def_method("baz", "qux")
  #m.def_protectedmethod("aaa")
  m.def_privatemethod("bbb")
  puts m.dump
end
