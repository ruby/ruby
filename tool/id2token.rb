#! /usr/bin/ruby -p
# -*- coding: us-ascii -*-

# Used to build the Ruby parsing code in common.mk and Ripper.

BEGIN {
  require 'optparse'
  $:.unshift(File.dirname(__FILE__))
  require 'vpath'
  vpath = VPath.new
  header = nil

  opt = OptionParser.new do |o|
    vpath.def_options(o)
    header = o.order!(ARGV).shift
  end or abort opt.opt_s

  TOKENS = {}
  h = vpath.read(header) rescue abort("#{header} not found in #{vpath.inspect}")
  h.scan(/^#define\s+RUBY_TOKEN_(\w+)\s+(\d+)/) do |token, id|
    TOKENS[token] = id
  end

  TOKENS_RE = /\bRUBY_TOKEN\((#{TOKENS.keys.join('|')})\)\s*(?=\s)/
}

$_.gsub!(TOKENS_RE) {TOKENS[$1]} if /^%token/ =~ $_
