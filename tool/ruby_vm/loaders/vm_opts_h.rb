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

require_relative '../helpers/scanner'

json    = {}
scanner = RubyVM::Scanner.new '../../../vm_opts.h'
grammar = %r/
    (?<ws>      \u0020 ){0}
    (?<key>     \w+    ){0}
    (?<value>   0|1    ){0}
    (?<define>  \G \#define \g<ws>+ OPT_\g<key> \g<ws>+ \g<value> \g<ws>*\n )
/mx

until scanner.eos? do
  if scanner.scan grammar then
    json[scanner['key']] = ! scanner['value'].to_i.zero? # not nonzero?
  else
    scanner.scan(/\G.*\n/)
  end
end

RubyVM::VmOptsH = json

if __FILE__ == $0 then
  require 'json'
  JSON.dump RubyVM::VmOptsH, STDOUT
end
