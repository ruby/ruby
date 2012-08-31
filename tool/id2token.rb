#! /usr/bin/ruby -p
BEGIN {
  require 'optparse'
  vpath = ["."]
  header = nil

  opt = OptionParser.new do |o|
    o.on('-v', '--vpath=DIR') {|dirs| vpath.concat dirs.split(File::PATH_SEPARATOR)}
    header = o.order!(ARGV).shift
  end or abort opt.opt_s

  TOKENS = {}
  vpath.find do |dir|
    begin
      h = File.read(File.join(dir, header))
    rescue Errno::ENOENT
      nil
    else
      h.scan(/^#define\s+RUBY_TOKEN_(\w+)\s+(\d+)/) do |token, id|
        TOKENS[token] = id
      end
      true
    end
  end or abort "#{header} not found in #{vpath.inspect}"

  TOKENS_RE = /\bRUBY_TOKEN\((#{TOKENS.keys.join('|')})\)\s*(?=\s)/
}

$_.gsub!(TOKENS_RE) {TOKENS[$1]} if /^%token/ =~ $_
