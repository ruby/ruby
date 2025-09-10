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

require_relative 'bare_instruction'
require_relative 'operands_unification'
require_relative 'instructions_unification'
require_relative 'trace_instruction'
require_relative 'zjit_instruction'

RubyVM::Instructions = RubyVM::BareInstruction.all +
                       RubyVM::OperandsUnification.all +
                       RubyVM::InstructionsUnification.all +
                       RubyVM::TraceInstruction.all +
                       RubyVM::ZJITInstruction.all
RubyVM::Instructions.freeze
