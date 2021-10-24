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
require_relative './vm_opts_h'

json    = []
scanner = RubyVM::Scanner.new '../../../insns.def'
path    = scanner.__FILE__
grammar = %r'
    (?<comment>  /[*] [^*]* [*]+ (?: [^*/] [^*]* [*]+ )* /         ){0}
    (?<keyword>  typedef | extern | static | auto | register |
                 struct  | union  | enum                           ){0}
    (?<C>        (?: \g<block> | [^{}]+ )*                         ){0}
    (?<block>    \{ \g<ws>*   \g<C>   \g<ws>* \}                   ){0}
    (?<ws>       \g<comment> | \s                                  ){0}
    (?<ident>    [_a-zA-Z] [0-9_a-zA-Z]*                           ){0}
    (?<type>     (?: \g<keyword> \g<ws>+ )* \g<ident>              ){0}
    (?<arg>      \g<type> \g<ws>+ \g<ident>                        ){0}
    (?<argv>     (?# empty ) |
                 void        |
                 (?: \.\.\. | \g<arg>) (?: \g<ws>* , \g<ws>* \g<arg> \g<ws>* )*  ){0}
    (?<pragma>   \g<ws>* // \s* attr \g<ws>+
                 (?<pragma:type> \g<type>   )              \g<ws>+
                 (?<pragma:name> \g<ident>  )              \g<ws>*
                 =                                         \g<ws>*
                 (?<pragma:expr> .+?;       )              \g<ws>* ){0}
    (?<insn>     DEFINE_INSN(_IF\((?<insn:if>\w+)\))?      \g<ws>+
                 (?<insn:name>   \g<ident>  )              \g<ws>*
     [(] \g<ws>* (?<insn:opes>   \g<argv>   ) \g<ws>* [)]  \g<ws>*
     [(] \g<ws>* (?<insn:pops>   \g<argv>   ) \g<ws>* [)]  \g<ws>*
     [(] \g<ws>* (?<insn:rets>   \g<argv>   ) \g<ws>* [)]  \g<ws>* ){0}
'x

until scanner.eos? do
  next if scanner.scan(/\G#{grammar}\g<ws>+/o)
  split = lambda {|v|
    case v when /\Avoid\z/ then
      []
    else
      v.split(/, */)
    end
  }

  l1   = scanner.scan!(/\G#{grammar}\g<insn>/o)
  name = scanner["insn:name"]
  opt  = scanner["insn:if"]
  ope  = split.(scanner["insn:opes"])
  pop  = split.(scanner["insn:pops"])
  ret  = split.(scanner["insn:rets"])
  if ope.include?("...")
    raise sprintf("parse error at %s:%d:%s: operands cannot be variadic",
                  scanner.__FILE__, scanner.__LINE__, name)
  end

  attrs = []
  while l2 = scanner.scan(/\G#{grammar}\g<pragma>/o) do
    attrs << {
      location: [path, l2],
      name: scanner["pragma:name"],
      type: scanner["pragma:type"],
      expr: scanner["pragma:expr"],
    }
  end

  l3 = scanner.scan!(/\G#{grammar}\g<block>/o)
  if opt.nil? || RubyVM::VmOptsH[opt]
    json << {
      name: name,
      location: [path, l1],
      signature: {
        name: name,
        ope: ope,
        pop: pop,
        ret: ret,
      },
      attributes: attrs,
      expr: {
        location: [path, l3],
        expr: scanner["block"],
      },
    }
  end
end

RubyVM::InsnsDef = json

if __FILE__ == $0 then
  require 'json'
  JSON.dump RubyVM::InsnsDef, STDOUT
end
