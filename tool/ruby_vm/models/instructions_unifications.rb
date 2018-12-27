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
require_relative '../loaders/opt_insn_unif_def'
require_relative 'bare_instructions'

class RubyVM::InstructionsUnifications
  include RubyVM::CEscape

  attr_reader :name

  def initialize opts = {}
    @location = opts[:location]
    @name     = namegen opts[:signature]
    @series   = opts[:signature].map do |i|
      RubyVM::BareInstructions.fetch i # Misshit is fatal
    end
  end

  private

  def namegen signature
    as_tr_cpp ['UNIFIED', *signature].join('_')
  end

  @instances = RubyVM::OptInsnUnifDef.map do |h|
    new h
  end

  def self.to_a
    @instances
  end
end
