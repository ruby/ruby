#! ./miniruby

dir = File.expand_path("../..", __FILE__)
$:.unshift(File.join(dir, "lib"))
$:.unshift(dir)
$:.unshift(".")
require 'mkmf'
require 'tool/serb'

mkin = File.read(File.join($srcdir, "Makefile.in"))
mkin.gsub!(/@(#{CONFIG.keys.join('|')})@/) {CONFIG[$1]}
if File.exist?(depend = File.join($srcdir, "depend"))
  tmp = ''
  eval(serb(File.read(depend), 'tmp'))
  mkin << "\n#### depend ####\n\n" << depend_rules(tmp).join
end
open(ARGV[0], 'w') {|f|
  f.puts mkin
}
