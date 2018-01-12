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

require_relative '../helpers/scanner'

json    = []
scanner = RubyVM::Scanner.new '../../../defs/opt_insn_unif.def'
path    = scanner.__FILE__
until scanner.eos? do
  next  if scanner.scan(/\G ^ (?: \#.* )? \n /x)
  break if scanner.scan(/\G ^ __END__ $ /x)

  pos = scanner.scan!(/\G (?<series>  (?: [\ \t]* \w+ )+ ) \n /mx)
  json << {
    location: [path, pos],
    signature: scanner["series"].strip.split
  }
end

RubyVM::OptInsnUnifDef = json

if __FILE__ == $0 then
  require 'json'
  JSON.dump RubyVM::OptInsnUnifDef, STDOUT
end
