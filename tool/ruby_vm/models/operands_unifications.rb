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

require_relative '../helpers/c_escape'
require_relative '../loaders/opt_operand_def'
require_relative 'bare_instructions'

class RubyVM::OperandsUnifications < RubyVM::BareInstructions
  include RubyVM::CEscape

  attr_reader :preamble, :original, :spec

  def initialize opts = {}
    name             = opts[:signature][0]
    @original        = RubyVM::BareInstructions.fetch name
    template         = @original.template
    parts            = compose opts[:location], opts[:signature], template[:signature]
    json             = template.dup
    json[:location]  = opts[:location]
    json[:signature] = parts[:signature]
    json[:name]      = parts[:name]
    @preamble        = parts[:preamble]
    @spec            = parts[:spec]
    super json.merge(:template => template)
    @konsts = parts[:vars]
    @konsts.each do |v|
      @variables[v[:name]] ||= v
    end
  end

  def operand_shift_of var
    before = @original.opes.find_index var
    after  = @opes.find_index var
    raise "no #{var} for #{@name}" unless before and after
    return before - after
  end

  def condition ptr
    # :FIXME: I'm not sure if this method should be in model?
    exprs = @spec.each_with_index.map do |(var, val), i|
      case val when '*' then
        next nil
      else
        type = @original.opes[i][:type]
        expr = RubyVM::Typemap.typecast_to_VALUE type, val
        next "#{ptr}[#{i}] == #{expr}"
      end
    end
    exprs.compact!
    if exprs.size == 1 then
      return exprs[0]
    else
      exprs.map! {|i| "(#{i})" }
      return exprs.join ' && '
    end
  end

  def has_ope? var
    super or @konsts.any? {|i| i[:name] == var[:name] }
  end

  private

  def namegen signature
    insn, argv = *signature
    wcary = argv.map do |i|
      case i when '*' then
        'WC'
      else
        i
      end
    end
    as_tr_cpp [insn, *wcary].join(', ')
  end

  def compose location, spec, template
    name    = namegen spec
    *, argv = *spec
    opes    = @original.opes
    if opes.size != argv.size
      raise sprintf("operand size mismatch for %s (%s's: %d, given: %d)",
                    name, template[:name], opes.size, argv.size)
    else
      src  = []
      mod  = []
      spec = []
      vars = []
      argv.each_index do |i|
        j = argv[i]
        k = opes[i]
        spec[i] = [k, j]
        case j when '*' then
          # operand is from iseq
          mod << k[:decl]
        else
          # operand is inside C
          vars << k
          src << {
            location: location,
            expr: "    const #{k[:decl]} = #{j};"
          }
        end
      end
      src.map! {|i| RubyVM::CExpr.new i }
      return {
        name: name,
        signature: {
          name: name,
          ope: mod,
          pop: template[:pop],
          ret: template[:ret],
        },
        preamble: src,
        vars: vars,
        spec: spec
      }
    end
  end

  @instances = RubyVM::OptOperandDef.map do |h|
    new h
  end

  def self.to_a
    @instances
  end

  def self.each_group
    to_a.group_by(&:original).each_pair do |k, v|
      yield k, v
    end
  end
end
