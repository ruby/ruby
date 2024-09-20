#! /your/favourite/path/to/ruby
# -*- Ruby -*-
# -*- frozen_string_literal: true; -*-
# -*- warn_indent: true; -*-
#
# Copyright (c) 2017 Urabe, Shyouhei.  All rights reserved.
#
# This file is  a part of the programming language  Ruby.  Permission is hereby
# granted, to  either redistribute and/or  modify this file, provided  that the
# conditions  mentioned in  the file  COPYING are  met.  Consult  the file  for
# details.

require_relative 'c_expr'

class RubyVM::Attribute
  include RubyVM::CEscape
  attr_reader :insn, :key, :type, :expr

  def initialize opts = {}
    @insn = opts[:insn]
    @key = opts[:name]
    @expr = RubyVM::CExpr.new location: opts[:location], expr: opts[:expr]
    @type = opts[:type]
    @ope_decls = @insn.operands.map do |operand|
      decl = operand[:decl]
      if @key == 'comptime_sp_inc' && operand[:type] == 'CALL_DATA'
        decl = decl.gsub('CALL_DATA', 'CALL_INFO').gsub('cd', 'ci')
      end
      decl
    end
  end

  def name
    as_tr_cpp "attr #{@key} @ #{@insn.name}"
  end

  def pretty_name
    "attr #{type} #{key} @ #{insn.pretty_name}"
  end

  def declaration
    if @ope_decls.empty?
      argv = "void"
    else
      argv = @ope_decls.join(', ')
    end
    sprintf '%s %s(%s)', @type, name, argv
  end

  def definition
    if @ope_decls.empty?
      argv = "void"
    else
      argv = @ope_decls.map {|decl| "MAYBE_UNUSED(#{decl})" }.join(",\n    ")
      argv = "\n    #{argv}\n" if @ope_decls.size > 1
    end
    sprintf "%s\n%s(%s)", @type, name, argv
  end
end
