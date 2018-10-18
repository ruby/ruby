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

require 'pathname'

# Poor man's StringScanner.
# Sadly  https://bugs.ruby-lang.org/issues/8343 is  not backported  to 2.0.  We
# have to do it by hand.
class RubyVM::Scanner
  attr_reader :__FILE__
  attr_reader :__LINE__

  def initialize path
    src       = Pathname.new(__FILE__).relative_path_from(Pathname.pwd).dirname
    src      += path
    @__LINE__ = 1
    @__FILE__ = src.to_path
    @str      = src.read mode: 'rt:utf-8:utf-8'
    @pos      = 0
  end

  def eos?
    return @pos >= @str.length
  end

  def scan re
    ret   = @__LINE__
    @last_match = @str.match re, @pos
    return unless @last_match
    @__LINE__ += @last_match.to_s.count "\n"
    @pos = @last_match.end 0
    return ret
  end

  def scan! re
    scan re or raise sprintf "parse error at %s:%d near:\n %s...", \
        @__FILE__, @__LINE__, @str[@pos, 32]
  end

  def [] key
    return @last_match[key]
  end
end
