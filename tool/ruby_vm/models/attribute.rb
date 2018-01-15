#! /your/favourite/path/to/ruby
# -*- mode: ruby; coding: utf-8; indent-tabs-mode: nil; ruby-indent-level: 2 -*-
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
  end

  def name
    as_tr_cpp "attr #{@key} @ #{@insn.name}"
  end

  def pretty_name
    "attr #{type} #{key} @ #{insn.pretty_name}"
  end

  def declaration
    opes = @insn.opes
    if opes.empty?
      argv = "void"
    else
      argv = opes.map {|o| o[:decl] }.join(', ')
    end
    sprintf '%s %s(%s)', @type, name, argv
  end

  def definition
    opes = @insn.opes
    if opes.empty?
      argv = "void"
    else
      argv = opes.map {|o| "MAYBE_UNUSED(#{o[:decl]})" }.join(",\n    ")
      argv = "\n    #{argv}\n" if opes.size > 1
    end
    sprintf "%s\n%s(%s)", @type, name, argv
  end
end
