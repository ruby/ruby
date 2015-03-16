#! /usr/local/bin/ruby -Kn
# usage: exyacc.rb [yaccfiles]
# this is coverted from exyacc.pl in the camel book

ARGF.each(nil) do |source|
  sbeg = source.index("\n%%") + 1
  send = source.rindex("\n%%") + 1
  grammar = source[sbeg, send-sbeg]
  grammar.sub!(/.*\n/, "")
  grammar.gsub!(/'\{'/, "'\001'")
  grammar.gsub!(/'\}'/, "'\002'")
  grammar.gsub!(%r{\*/}, "\003\003")
  grammar.gsub!(%r{/\*[^\003]*\003\003}, '')
  while grammar.gsub!(/\{[^{}]*\}/, ''); end
  grammar.gsub!(/'\001'/, "'{'")
  grammar.gsub!(/'\002'/, "'}'")
  while grammar.gsub!(/^[ \t]*\n(\s)/, '\1'); end
  grammar.gsub!(/([:|])[ \t\n]+(\w)/, '\1 \2')
  print grammar
end
