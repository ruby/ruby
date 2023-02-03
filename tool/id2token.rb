#! /usr/bin/ruby -p
# -*- coding: us-ascii -*-

# Used to build the Ruby parsing code in common.mk and Ripper.

BEGIN {
  require 'optparse'

  opt = OptionParser.new do |o|
    o.order!(ARGV)
  end or abort opt.opt_s

  TOKENS = {}
  defs = File.join(File.dirname(File.dirname(__FILE__)), "defs/id.def")
  ids = eval(File.read(defs), nil, defs)
  ids[:token_op].each do |_id, _op, token, id|
    TOKENS[token] = id
  end

  TOKENS_RE = /\bRUBY_TOKEN\((#{TOKENS.keys.join('|')})\)\s*(?=\s)/
}

$_.gsub!(TOKENS_RE) {TOKENS[$1]} if /^%token/ =~ $_
