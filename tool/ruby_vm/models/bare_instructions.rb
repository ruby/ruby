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

require_relative '../loaders/insns_def'
require_relative 'c_expr'
require_relative 'typemap'
require_relative 'attribute'

class RubyVM::BareInstructions
  attr_reader :template, :name, :opes, :pops, :rets, :decls, :expr

  def initialize opts = {}
    @template = opts[:template]
    @name     = opts[:name]
    @loc      = opts[:location]
    @sig      = opts[:signature]
    @expr     = RubyVM::CExpr.new opts[:expr]
    @opes     = typesplit @sig[:ope]
    @pops     = typesplit @sig[:pop].reject {|i| i == '...' }
    @rets     = typesplit @sig[:ret].reject {|i| i == '...' }
    @attrs    = opts[:attributes].map {|i|
      RubyVM::Attribute.new i.merge(:insn => self)
    }.each_with_object({}) {|a, h|
      h[a.key] = a
    }
    @attrs_orig = @attrs.dup
    check_attribute_consistency
    predefine_attributes
  end

  def pretty_name
    n = @sig[:name]
    o = @sig[:ope].map{|i| i[/\S+$/] }.join ', '
    p = @sig[:pop].map{|i| i[/\S+$/] }.join ', '
    r = @sig[:ret].map{|i| i[/\S+$/] }.join ', '
    return sprintf "%s(%s)(%s)(%s)", n, o, p, r
  end

  def bin
    return "BIN(#{name})"
  end

  def call_attribute name
    return sprintf 'attr_%s_%s(%s)', name, @name, \
                   @opes.map {|i| i[:name] }.compact.join(', ')
  end

  def has_attribute? k
    @attrs_orig.has_key? k
  end

  def attributes
    return @attrs           \
      . sort_by {|k, _| k } \
      . map     {|_, v| v }
  end

  def width
    return 1 + opes.size
  end

  def declarations
    return @variables                                        \
      . values                                               \
      . group_by {|h| h[:type] }                             \
      . sort_by  {|t, v| t }                                 \
      . map      {|t, v| [t, v.map {|i| i[:name] }.sort ] }  \
      . map      {|t, v|
        sprintf("MAYBE_UNUSED(%s) %s", t, v.join(', '))
      }
  end

  def preamble
    # preamble makes sense for operand unifications
    return []
  end

  def sc?
    # sc stands for stack caching.
    return false
  end

  def cast_to_VALUE var, expr = var[:name]
    RubyVM::Typemap.typecast_to_VALUE var[:type], expr
  end

  def cast_from_VALUE var, expr = var[:name]
    RubyVM::Typemap.typecast_from_VALUE var[:type], expr
  end

  def operands_info
    opes.map {|o|
      c, _ = RubyVM::Typemap.fetch o[:type]
      next c
    }.join
  end

  def handles_sp?
    /\b(false|0)\b/ !~ @attrs.fetch('handles_sp').expr.expr
  end

  def always_leaf?
    @attrs.fetch('leaf').expr.expr == 'true;'
  end

  def leaf_without_check_ints?
    @attrs.fetch('leaf').expr.expr == 'leafness_of_check_ints;'
  end

  def handle_canary stmt
    # Stack canary is basically a good thing that we want to add, however:
    #
    # - When the instruction returns variadic number of return values,
    #   it is not easy to tell where is the stack top.  We can't but
    #   skip it.
    #
    # - When the instruction body is empty (like putobject), we can
    #   say for 100% sure that canary is a waste of time.
    #
    # So we skip canary for those cases.
    return '' if @sig[:ret].any? {|i| i == '...' }
    return '' if @expr.blank?
    return "    #{stmt};\n"
  end

  def inspect
    sprintf "#<%s %s@%s:%d>", self.class.name, @name, @loc[0], @loc[1]
  end

  def has_ope? var
    return @opes.any? {|i| i[:name] == var[:name] }
  end

  def has_pop? var
    return @pops.any? {|i| i[:name] == var[:name] }
  end

  def use_call_data?
    @use_call_data ||=
      @variables.find { |_, var_info| var_info[:type] == 'CALL_DATA' }
  end

  private

  def check_attribute_consistency
    if has_attribute?('sp_inc') \
        && use_call_data? \
        && !has_attribute?('comptime_sp_inc')
      # As the call cache caches information that can only be obtained at
      # runtime, we do not need it when compiling from AST to bytecode. This
      # attribute defines an expression that computes the stack pointer
      # increase based on just the call info to avoid reserving space for the
      # call cache at compile time. In the expression, all call data operands
      # are mapped to their call info counterpart. Additionally, all mentions
      # of `cd` in the operand name are replaced with `ci`.
      raise "Please define attribute `comptime_sp_inc` for `#{@name}`"
    end
  end

  def generate_attribute t, k, v
    @attrs[k] ||= RubyVM::Attribute.new \
      insn: self,                       \
      name: k,                          \
      type: t,                          \
      location: [],                     \
      expr: v.to_s + ';'
    return @attrs[k] ||= attr
  end

  def predefine_attributes
    # Beware: order matters here because some attribute depends another.
    generate_attribute 'const char*', 'name', "insn_name(#{bin})"
    generate_attribute 'enum ruby_vminsn_type', 'bin', bin
    generate_attribute 'rb_num_t', 'open', opes.size
    generate_attribute 'rb_num_t', 'popn', pops.size
    generate_attribute 'rb_num_t', 'retn', rets.size
    generate_attribute 'rb_num_t', 'width', width
    generate_attribute 'rb_snum_t', 'sp_inc', rets.size - pops.size
    generate_attribute 'bool', 'handles_sp', default_definition_of_handles_sp
    generate_attribute 'bool', 'leaf', default_definition_of_leaf
  end

  def default_definition_of_handles_sp
    # Insn with ISEQ should yield it; can handle sp.
    return opes.any? {|o| o[:type] == 'ISEQ' }
  end

  def default_definition_of_leaf
    # Insn that handles SP can never be a leaf.
    if not has_attribute? 'handles_sp' then
      return ! default_definition_of_handles_sp
    elsif handles_sp? then
      return "! #{call_attribute 'handles_sp'}"
    else
      return true
    end
  end

  def typesplit a
    @variables ||= {}
    a.map do |decl|
      md = %r'
        (?<comment> /[*] [^*]* [*]+ (?: [^*/] [^*]* [*]+ )* / ){0}
        (?<ws>      \g<comment> | \s                          ){0}
        (?<ident>   [_a-zA-Z] [0-9_a-zA-Z]*                   ){0}
        (?<type>    (?: \g<ident> \g<ws>+ )* \g<ident>        ){0}
        (?<var>     \g<ident>                                 ){0}
        \G          \g<ws>* \g<type> \g<ws>+ \g<var>
      'x.match(decl)
      @variables[md['var']] ||= {
        decl: decl,
        type: md['type'],
        name: md['var'],
      }
    end
  end

  @instances = RubyVM::InsnsDef.map {|h|
    new h.merge(:template => h)
  }

  def self.fetch name
    @instances.find do |insn|
      insn.name == name
    end or raise IndexError, "instruction not found: #{name}"
  end

  def self.to_a
    @instances
  end
end
