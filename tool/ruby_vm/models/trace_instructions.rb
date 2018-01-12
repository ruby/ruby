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

require_relative '../helpers/c_escape'
require_relative 'bare_instructions'

class RubyVM::TraceInstructions
  include RubyVM::CEscape

  attr_reader :name

  def initialize orig
    @orig = orig
    @name = as_tr_cpp "trace @ #{@orig.name}"
  end

  def pretty_name
    return sprintf "%s(...)(...)(...)", @name
  end

  def jump_destination
    return @orig.name
  end

  def bin
    return sprintf "BIN(%s)", @name
  end

  def width
    return @orig.width
  end

  def operands_info
    return @orig.operands_info
  end

  def rets
    return ['...']
  end

  def pops
    return ['...']
  end

  def attributes
    return []
  end

  def has_attribute? *;
    return false
  end

  private

  @instances = RubyVM::Instructions.map {|i| new i }

  def self.to_a
    @instances
  end

  RubyVM::Instructions.push(*to_a)
end
