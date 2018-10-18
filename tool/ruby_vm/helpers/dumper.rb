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
require 'erb'
require_relative 'c_escape'

class RubyVM::Dumper
  include RubyVM::CEscape
  private

  def new_binding
    # This `eval 'binding'` does not return the current binding
    # but creates one on top of it.
    return eval 'binding'
  end

  def new_erb spec
    path  = Pathname.new(__FILE__).relative_path_from(Pathname.pwd).dirname
    path += '../views'
    path += spec
    src   = path.read mode: 'rt:utf-8:utf-8'
  rescue Errno::ENOENT
    raise "don't know how to generate #{path}"
  else
    if ERB.instance_method(:initialize).parameters.assoc(:key) # Ruby 2.6+
      erb = ERB.new(src, trim_mode: '%-')
    else
      erb = ERB.new(src, nil, '%-')
    end
    erb.filename = path.to_path
    return erb
  end

  def finderb spec
    return @erb.fetch spec do |k|
      erb = new_erb k
      @erb[k] = erb
    end
  end

  def replace_pragma_line str, lineno
    if str == "#pragma RubyVM reset source\n" then
      return "#line #{lineno + 2} #{@file}\n"
    else
      return str
    end
  end

  def local_variable_set bnd, var, val
    eval '__locals__ ||= {}', bnd
    locals = eval '__locals__', bnd
    locals[var] = val
    eval "#{var} = __locals__[:#{var}]", bnd
    test = eval "#{var}", bnd
    raise unless test == val
  end

  public

  def do_render source, locals
    erb = finderb source
    bnd = @empty.dup
    locals.each_pair do |k, v|
      local_variable_set bnd, k, v
    end
    return erb.result bnd
  end

  def replace_pragma str
    return str                                 \
      . each_line                              \
      . with_index                             \
      . map {|i, j| replace_pragma_line i, j } \
      . join
  end

  def initialize dst
    @erb   = {}
    @empty = new_binding
    @file  = cstr dst.to_path
  end

  def render partial, opts = { :locals => {} }
    return do_render "_#{partial}.erb", opts[:locals]
  end

  def generate template
    str = do_render "#{template}.erb", {}
    return replace_pragma str
  end

  private

  # view helpers

  alias cstr rstring2cstr
  alias comm commentify

  def render_c_expr expr
    render 'c_expr', locals: { expr: expr, }
  end
end
