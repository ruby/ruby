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

RubyVM::Typemap = {
  "..."            => %w[. TS_VARIABLE],
  "CALL_DATA"      => %w[C TS_CALLDATA],
  "CDHASH"         => %w[H TS_CDHASH],
  "IC"             => %w[K TS_IC],
  "IVC"            => %w[A TS_IVC],
  "ICVARC"         => %w[J TS_ICVARC],
  "ID"             => %w[I TS_ID],
  "ISE"            => %w[T TS_ISE],
  "ISEQ"           => %w[S TS_ISEQ],
  "OFFSET"         => %w[O TS_OFFSET],
  "VALUE"          => %w[V TS_VALUE],
  "lindex_t"       => %w[L TS_LINDEX],
  "rb_insn_func_t" => %w[F TS_FUNCPTR],
  "rb_num_t"       => %w[N TS_NUM],
  "RB_BUILTIN"     => %w[R TS_BUILTIN],
}

# :FIXME: should this method be here?
class << RubyVM::Typemap
  def typecast_from_VALUE type, val
    # see also iseq_set_sequence()
    case type
    when '...'
      raise "cast not possible: #{val}"
    when 'VALUE' then
      return val
    when 'rb_num_t', 'lindex_t' then
      return "NUM2LONG(#{val})"
    when 'ID' then
      return "SYM2ID(#{val})"
    else
      return "(#{type})(#{val})"
    end
  end

  def typecast_to_VALUE type, val
    case type
    when 'VALUE' then
      return val
    when 'ISEQ', 'rb_insn_func_t' then
      return "(VALUE)(#{val})"
    when 'rb_num_t', 'lindex_t'
      "LONG2NUM(#{val})"
    when 'ID' then
      return "ID2SYM(#{val})"
    else
      raise ":FIXME: TBW for #{type}"
    end
  end
end
