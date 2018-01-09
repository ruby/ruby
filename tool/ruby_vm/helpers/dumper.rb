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

  # I learned this handy "super-private" maneuver from @a_matsuda
  # cf: https://github.com/rails/rails/pull/27363/files
  using Module.new {
    refine RubyVM::Dumper do
      private

      def new_binding
        # This `eval 'binding'` does not return the current binding
        # but creates one on top of it.
        return eval 'binding'
      end

      def new_erb spec
        path  = Pathname.new __dir__
        path += '../views'
        path += spec
        src   = path.read mode: 'rt:utf-8:utf-8'
      rescue Errno::ENOENT
        raise "don't know how to generate #{path}"
      else
        erb = ERB.new src, nil, '%-'
        erb.filename = path.realpath.to_path
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

      public

      def do_render source, locals
        erb = finderb source
        bnd = @empty.dup
        locals.each_pair do |k, v|
          bnd.local_variable_set k, v
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
    end
  }

  def initialize path
    @erb   = {}
    @empty = new_binding
    dst    = Pathname.new Dir.getwd
    dst   += path
    @file  = cstr dst.realdirpath.to_path
  end

  def render partial, locals: {}
    return do_render "_#{partial}.erb", locals
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
