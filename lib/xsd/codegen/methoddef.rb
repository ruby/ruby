# XSD4R - Generating method definition code
# Copyright (C) 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/codegen/gensupport'
require 'xsd/codegen/commentdef'


module XSD
module CodeGen


class MethodDef
  include GenSupport
  include CommentDef

  attr_accessor :definition

  def initialize(name, *params)
    unless safemethodname?(name)
      raise ArgumentError.new("name '#{name}' seems to be unsafe")
    end
    @name = name
    @params = params
    @comment = nil
    @definition = yield if block_given?
  end

  def dump
    buf = ""
    buf << dump_comment if @comment
    buf << dump_method_def
    buf << dump_definition if @definition
    buf << dump_method_def_end
    buf
  end

private

  def dump_method_def
    if @params.empty?
      format("def #{@name}")
    else
      format("def #{@name}(#{@params.join(", ")})")
    end
  end

  def dump_method_def_end
    format("end")
  end

  def dump_definition
    format(@definition, 2)
  end
end


end
end
