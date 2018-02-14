#! /your/favourite/path/to/miniruby
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

# This class roughly mimics C preprocessor behaviour defined in ISO 9899.  Note
# however  that we  _don't_ implement  full C  preprocessor features.   What is
# understood is a very  limited part of it because we can  control the input to
# avoid glitchy corner cases.
#
# Assumptions:
#  - Trigraphs never appear.
#  - Second and later inclusion of a same header file can be ignored.
#  - No complicated integer calculations are needed to tell if we should
#    include a file or not.
class RubyVM::Preprocessor

  attr_reader :preprocess

  private

  def initialize path
    @pwd        = Dir.getwd
    @srcdir     = File.dirname path
    @macros     = {}
    @headers    = []
    @preprocess = include path
  end

  # The "phase"s here are what ISO 9899 section 5.1.1.2 is talking about.

  def phase1 str
    str.gsub! %r/#{Grammar}\g<trigraph>/o do
      raise %'trigraph "#{$&}" found! must be a bug.'
    end
  end

  def phase2 str
    str.gsub! %r/#{Grammar}\\(?:\g<CR>|\g<LF>|\g<CR>\g<LF>)/o, ''
  end

  def phase3 str
    str.gsub! %r/#{Grammar}\g<\s>+/o, "\u0020"
  end

  def phase4 str
    # phase 4 is what people normally think "the" C preprocessor.
    ary = []
    pos = 0
    len = str.length
    while pos < len do
      case
      when m = /#{Grammar}\G\g<#define>/o.match(str, pos) then
        expr = define m
      when m = /#{Grammar}\G\g<#undef>/o.match(str, pos) then
        expr = undef! m
      when m = /#{Grammar}\G\g<#ifX>/o.match(str, pos) then
        expr = ifdef m
      when m = /#{Grammar}\G\g<#include>/o.match(str, pos) then
        expr = include m['"..."'][1..-2]
      when m = /#{Grammar}\G\g<#line>/o.match(str, pos) then
        expr = m
      when m = /#{Grammar}\G\g<#error>/o.match(str, pos) then
        expr = m
      when m = /#{Grammar}\G\g<#pragma>/o.match(str, pos) then
        expr = m
      when m = /#{Grammar}\G\g<#endif>/o.match(str, pos) then
        raise [str[0..pos], str[pos, 32]].inspect # NOTREACHED
      else
        m = /#{Grammar}\G(?m:.+?(?=\g<#>|\z))/o.match(str, pos)
        expr = m
      end
      pos = m.end(0)
      ary << expr
    end
    str.replace ary.join
  end

  def defined ident
    return @macros.has_key? ident
  end

  def define md
    ident = md['ident'].freeze
    expr  = md['macro'].freeze
    @macros.store(ident, expr)
    return md
  end

  def undef! md
    ident = md['ident']
    @macros.delete ident
    return md
  end

  def include path
    target = find path
    if @headers.include? target
      debug "skipping #include \"%s\"\n", path
      return ''
    else
      @headers << target
      debug "processing #include \"%s\"\n", path
      str = File.read(target, mode: 'rb:utf-8')
      phase1 str
      phase2 str
      phase3 str
      phase4 str
      str.gsub! %r/(^ *\n)+/, "\n" # cut empty lines for aesthetic reason
      return str
    end
  end

  def ifdef md
    str = md.string
    pos = md.begin(0)

    case
    when m = /#{Grammar}\G\g<#ifdef>/o.match(str, pos) then
      expr = defined(m['ident']) ? 1 : 0
    when m = /#{Grammar}\G\g<#ifndef>/o.match(str, pos) then
      expr = defined(m['ident']) ? 0 : 1
    when m = /#{Grammar}\G\g<#if>/o.match(str, pos) then
      expr = eval m['expr']
    when m = /#{Grammar}\G\g<#elif>/o.match(str, pos) then
      expr = eval m['expr']
    else
      raise str[pos, 32].dump
    end

    m1 = %r/#{Grammar}\G
      (?<strict-body> \g<#ifX> |
        (?! \g<#elif> )
        (?! \g<#else> )
        (?! \g<#endif> )
        .*? \g<\n>
      ){0}          (?<then-body> \g<strict-body>+ )  ?
      (?: \g<#elif> (?<elif-body> \g<strict-body>+ ) )*
      (?: \g<#else> (?<else-body> \g<strict-body>+ ) )?
      \g<#endif>
    /ox.match(str, m.end(0))

    if expr != 0 then
      return phase4(m1['then-body'] || '')
    elsif m1['#elif'] then
      start = m1.end('then-body') || m.end(0)
      substr = str.slice(start...md.end(0))
      substr.sub! %r/#{Grammar}\A\g<#>elif/, '#if' or raise substr.inspect
      return ifdef %r/#{Grammar}\G\g<#ifX>/.match(substr)
    elsif m1['else-body'] then
      return phase4 m1['else-body']
    else
      return ''
    end
  end

  def absolute? path
    while true do
      dir = File.dirname(path)
      if dir == path then
        return dir != '.'
      else
        path = dir
      end
    end
  end

  def find target
    if absolute? target then
      return target
    else
      pat = "{#@srcdir{,/include{,/ruby}},#@pwd{,/.ext/include/*}}/#{target}"
      Dir.glob pat do |ret|
        return ret
      end
    end
    raise "cant find #{target} based #{@srcdir.inspect} / #{@pwd.inspect}"
  end

  def fcall md
    defs   = @macros.fetch(md['ident'])
    params = /\((.*?)\)/.match(md[0])
    vars   = /\((.*?)\)/.match(defs)
    return md[0].sub md['ident'], defs unless vars
    ret    = vars.post_match.dup
    params = params[1].split(/\s*,\s*/)
    vars   = vars[1].split(/\s*,\s*/)
    params.zip vars do |(p, v)|
      val = eval p
      ret.gsub! v, val.to_s
    end
    ret.strip!
    ret
  end

  def eval str
    str, str0 = str.dup, str
    str.strip!
    str.gsub! %r/#{Grammar}\g<defined>/o do
      defined($~['ident']) ? "1" : "0"
    end
    str.gsub! %r/#{Grammar}\g<fcall>/o do
      fcall $~
    end
    str.gsub! %r/#{Grammar}\g<ident>/o do
      @macros.fetch($~['ident'], "0").strip
    end
    str.gsub! %r/#{Grammar}\g<paren>/o do
      eval $~['paren'][1..-2]
    end
    str.gsub! %r/#{Grammar}\g<notop>\g<expr>/o do
      eval($~['expr']) == 0 ? "1" : "0"
    end
    break unless str.gsub! %r/#{Grammar}\g<L>\g<andop>\g<R>/o do
      eval($~['L']) == 0 ? "0" : eval($~['R'])
    end while true
    break unless str.gsub! %r/#{Grammar}\g<L>\g<orop>\g<R>/o do
      eval($~['L']) != 0 ? eval($~['R']) : "0"
    end while true
    str.gsub! %r/#{Grammar}\g<L>\g<ltlt>\g<R>/o do
      eval($~['L']) << eval($~['R'])
    end
    str.gsub! %r/#{Grammar}\g<L>\g<lt>\g<R>/o do
      eval($~['L']) < eval($~['R']) ? "1" : "0"
    end
    str.gsub! %r/#{Grammar}\g<L>\g<le>\g<R>/o do
      eval($~['L']) <= eval($~['R']) ? "1" : "0"
    end
    str.gsub! %r/#{Grammar}\g<L>\g<gt>\g<R>/o do
      eval($~['L']) > eval($~['R']) ? "1" : "0"
    end
    str.gsub! %r/#{Grammar}\g<L>\g<ge>\g<R>/o do
      eval($~['L']) >= eval($~['R']) ? "1" : "0"
    end
    str.gsub! %r/#{Grammar}\g<L>\g<eq>\g<R>/o do
      eval($~['L']) == eval($~['R']) ? "1" : "0"
    end
    str.gsub! %r/#{Grammar}\g<L>\g<ne>\g<R>/o do
      eval($~['L']) != eval($~['R']) ? "1" : "0"
    end
    str.gsub! %r/#{Grammar}\g<L>\g<mul>\g<R>/o do
      eval($~['L']) * eval($~['R'])
    end
    str.gsub! %r/#{Grammar}\g<L>\g<div>\g<R>/o do
      eval($~['L']) / eval($~['R'])
    end
    str.gsub! %r/#{Grammar}\g<L>\g<add>\g<R>/o do
      eval($~['L']) + eval($~['R'])
    end
    str.gsub! %r/#{Grammar}\g<L>\g<sub>\g<R>/o do
      eval($~['L']) - eval($~['R'])
    end
    if n = str.to_i then
      return n
    else
      raise "(#{str0.dump}=>#{str.dump}: unknown expr)"
    end
  rescue RuntimeError => e1
    raise SyntaxError, e1.message
  rescue SyntaxError => e2
    raise SyntaxError, "#{str0.dump}=>(#{str.dump}=>#{e2})"
  end

  if $DEBUG then
    def debug(*argv)
      STDERR.printf(*argv)
    end
  else
    def debug(*)
    end
  end

  Grammar =%r(
    (?<TAB>      \u0009                                          ){0}
    (?<LF>       \u000A                                          ){0}
    (?<VT>       \u000B                                          ){0}
    (?<FF>       \u000C                                          ){0}
    (?<CR>       \u000D                                          ){0}
    (?<SP>       \u0020                                          ){0}
    (?<\s>       \g</* */> | \g<SP> | \g<TAB> | \g<VT> | \g<FF>  ){0}
    (?<\n>       \g<\s>* (?: \g<CR> | \g<LF> | \g<CR> \g<LF> )   ){0}
    (?</* */>    /\* [^*]* \*+ (?: [^*/] [^*]* \*+ )* /          ){0}
    (?<"...">    " (?: \\ . | [^"\\] )* "                        ){0}
    (?<#>        ^ \g<\s>* \# \g<\s>*                            ){0}
    (?<trigraph> \u003f \u003f [=/'()!<>-]                       ){0}
    (?<ident>    [A-Za-z_] [A-Za-z_0-9]*                         ){0}
    (?<#include> \g<#> include \g<\s>* \g<"...">          \g<\n> ){0}
    (?<#ifndef>  \g<#> ifndef  \g<\s>+ \g<ident>          \g<\n> ){0}
    (?<#ifdef>   \g<#> ifdef   \g<\s>+ \g<ident>          \g<\n> ){0}
    (?<#if>      \g<#> if      \g<\s>+ \g<expr>           \g<\n> ){0}
    (?<#elif>    \g<#> elif    \g<\s>+ \g<expr>           \g<\n> ){0}
    (?<#else>    \g<#> else                               \g<\n> ){0}
    (?<#endif>   \g<#> endif                              \g<\n> ){0}
    (?<#undef>   \g<#> undef  \g<\s>+ \g<ident>           \g<\n> ){0}
    (?<#define>  \g<#> define \g<\s>+ \g<ident> \g<macro> \g<\n> ){0}
    (?<#error>   \g<#> error .+                           \g<\n> ){0}
    (?<#line>    \g<#> line .+                            \g<\n> ){0}
    (?<#pragma>  \g<#> pragma .+                          \g<\n> ){0}
    (?<macro>    (?: \( .+? \) )? \g<\s>+ \g<expr>               ){0}
    (?<expr>     (?: [A-Za-z0-9_!] | \g<paren> ) .*              ){0}
    (?<fcall>    \g<ident> \g<\s>* \( .+? \)                     ){0}
    (?<body>     (?: \g<#ifX> | (?! \g<#endif> ) .*\n )          ){0}
    (?<#ifX>     \g<#> if .+ \g<\n> \g<body>* \g<#endif>         ){0}
    (?<numeric>  (?: 0 | [1-9] [0-9]* ) (?i: u? l? )             ){0}
    (?<paren>    \( (?: \g<paren> | [^()] + )+ \)                ){0}
    (?<L>        \g<expr>                                        ){0}
    (?<R>        \g<expr>                                        ){0}
    (?<notop>        \! (?!=) \g<\s>*                            ){0}
    (?<andop>    \g<\s>* &&   \g<\s>*                            ){0}
    (?<orop>     \g<\s>* \|\| \g<\s>*                            ){0}
    (?<lt>       \g<\s>* \<   \g<\s>*                            ){0}
    (?<le>       \g<\s>* \<=  \g<\s>*                            ){0}
    (?<gt>       \g<\s>* \>   \g<\s>*                            ){0}
    (?<ge>       \g<\s>* \>=  \g<\s>*                            ){0}
    (?<eq>       \g<\s>* ==   \g<\s>*                            ){0}
    (?<ne>       \g<\s>* !=   \g<\s>*                            ){0}
    (?<mul>      \g<\s>* \*   \g<\s>*                            ){0}
    (?<div>      \g<\s>* \/   \g<\s>*                            ){0}
    (?<add>      \g<\s>* \+   \g<\s>*                            ){0}
    (?<sub>      \g<\s>* \-   \g<\s>*                            ){0}
    (?<ltlt>     \g<\s>* \<\< \g<\s>*                            ){0}
    (?<defined>  defined \g<\s>* \g<ident>
              |  defined \g<\s>* \( \g<\s>* \g<ident> \g<\s>* \) ){0}
  )x
end

if __FILE__ == $0 then
  puts RubyVM::Preprocessor.new(ARGV[0]).preprocess
end
