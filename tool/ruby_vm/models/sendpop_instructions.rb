#! /your/favourite/path/to/ruby
# -*- Ruby -*-
# -*- frozen_string_literal: true; -*-
# -*- warn_indent: true; -*-
#
# Copyright (c) 2019 Urabe, Shyouhei.  All rights reserved.
#
# This file is  a part of the programming language  Ruby.  Permission is hereby
# granted, to  either redistribute and/or  modify this file, provided  that the
# conditions  mentioned in  the file  COPYING are  met.  Consult  the file  for
# details.

require_relative 'bare_instructions'
require_relative 'typemap'

class RubyVM::SendpopInstructions < RubyVM::BareInstructions
  attr_reader :orig_rets

  def initialize orig
    str = Marshal.dump orig.template
    json = Marshal.load str
    json[:name] = "opt_sendpop_#{orig.name}"
    json[:signature][:ret] = []
    super json
    # The original return value should be declared -- though it is discarded --
    # to prevent compile errors.
    @orig_rets = orig.rets
    # @variables  is  used  in _mjit_compile_insn.erb  (via  #declarations)  so
    # cannot omit.
    orig.rets.each do |ret|
      @variables[ret[:name]] ||= ret
    end
  end

  private

  re = %r/#{RubyVM::Typemap["CALL_INFO"].first}/o # => /C/
  @instances =                            \
    RubyVM::Instructions                  \
    . select {|i| re =~ i.operands_info } \
    . map    {|i| new i }

  def self.to_a
    @instances
  end

  RubyVM::Instructions.push(*to_a)
end
