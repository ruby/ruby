#! ./miniruby

dir = File.expand_path("../..", __FILE__)
$:.unshift(File.join(dir, "lib"))
$:.unshift(dir)
$:.unshift(".")
require 'mkmf'
require 'tool/serb'

if /--builtin-encs=/ =~ ARGV[0]
  BUILTIN_ENCS = $'.split.each {|e| e.sub!(/(?:\.\w+)?\z/, '.c')}
  ARGV.shift
else
  BUILTIN_ENCS = []
end

DEFFILE = (true if CONFIG["DLDFLAGS"].sub!(/\s+-def:\$\(DEFFILE\)\s+/, ' '))
  
mkin = File.read(File.join($srcdir, "Makefile.in"))
mkin.gsub!(/@(#{CONFIG.keys.join('|')})@/) {CONFIG[$1]}
if File.exist?(depend = File.join($srcdir, "depend"))
  tmp = ''
  eval(serb(File.read(depend), 'tmp'), binding, depend)
  mkin << "\n#### depend ####\n\n" << depend_rules(tmp).join
end
open(ARGV[0], 'wb') {|f|
  f.puts mkin
}
