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

require_relative '../helpers/c_escape.rb'

class RubyVM::CExpr
  include RubyVM::CEscape

  attr_reader :__FILE__, :__LINE__, :expr

  def initialize location:, expr:
    @__FILE__  = location[0]
    @__LINE__  = location[1]
    @expr      = expr
  end

  # blank, in sense of C program.
  RE = %r'\A{\g<s>*}\z|\A(?<s>\s|/[*][^*]*[*]+([^*/][^*]*[*]+)*/)*\z'
  if RUBY_VERSION > '2.4' then
    def blank?
      RE.match? @expr
    end
  else
    def blank?
      RE =~ @expr
    end
  end

  def inspect
    sprintf "#<%s:%d %s>", @__FILE__, @__LINE__, @expr
  end
end
