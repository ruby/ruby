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

require_relative 'bare_instructions'
require_relative 'operands_unifications'
require_relative 'instructions_unifications'

RubyVM::Instructions = RubyVM::BareInstructions.to_a + \
                       RubyVM::OperandsUnifications.to_a + \
                       RubyVM::InstructionsUnifications.to_a

require_relative 'trace_instructions'
RubyVM::Instructions.freeze
