#! /usr/local/bin/ruby -Kn
# usage: exyacc.rb [yaccfiles]
# this is coverted from exyacc.pl in the camel book

$/ = nil

while gets()
  sbeg = $_.index("\n%%") + 1
  send = $_.rindex("\n%%") + 1
  $_ = $_[sbeg, send-sbeg]
  sub!(/.*\n/, "")
  gsub!(/'\{'/, "'\001'")
  gsub!(/'}'/, "'\002'")
  gsub!('\*/', "\003\003")
  gsub!("/\\*[^\003]*\003\003", '')
  while gsub!(/\{[^{}]*}/, ''); end
  gsub!(/'\001'/, "'{'")
  gsub!(/'\002'/, "'}'")
  while gsub!(/^[ \t]*\n(\s)/, '\1'); end
  gsub!(/([:|])[ \t\n]+(\w)/, '\1 \2')
  print $_
end
