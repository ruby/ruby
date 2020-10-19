#! /your/favourite/path/to/ruby
# -*- Ruby -*-
# -*- frozen_string_literal: true; -*-
# -*- warn_indent: true; -*-
#
# Copyright (c) 2020 Wu, Alan.  All rights reserved.
#
# This file is  a part of the programming language  Ruby.  Permission is hereby
# granted, to  either redistribute and/or  modify this file, provided  that the
# conditions  mentioned in  the file  COPYING are  met.  Consult  the file  for
# details.

class RubyVM::MicroJIT::ExampleInstructions
  include RubyVM::CEscape

  attr_reader :name, :call_line

  def initialize(name, call_line)
    @name = name
    @call_line = call_line
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
    1
  end

  def operands_info
    ""
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

  def handles_sp?
    false
  end

  def always_leaf?
    false
  end

  @all_examples = [
    new('ujit_call_example', 'reg_pc = rb_ujit_empty_func(GET_CFP());'),
    new('ujit_call_example_with_ec', 'reg_pc = rb_ujit_empty_func_with_ec(GET_CFP(), ec);')
  ]

  def self.to_a
    @all_examples
  end
end
