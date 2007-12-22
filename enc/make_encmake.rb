#! ./miniruby

dir = File.expand_path("../..", __FILE__)
$:.unshift(File.join(dir, "lib"))
$:.unshift(dir)
$:.unshift(".")
require 'mkmf'
require 'erb'

if /--builtin-encs=/ =~ ARGV[0]
  BUILTIN_ENCS = $'.split.map {|e| File.basename(e, '.*') << '.c'}
  ARGV.shift
else
  BUILTIN_ENCS = []
end

DEFFILE = (true if CONFIG["DLDFLAGS"].sub!(/\s+-def:\$\(DEFFILE\)\s+/, ' '))
  
mkin = File.read(File.join($srcdir, "Makefile.in"))
mkin.gsub!(/@(#{CONFIG.keys.join('|')})@/) {CONFIG[$1]}
if File.exist?(depend = File.join($srcdir, "depend"))
  erb = ERB.new(File.read(depend), nil, '%')
  erb.filename = depend
  tmp = erb.result(binding)
  mkin << "\n#### depend ####\n\n" << depend_rules(tmp).join
end
open(ARGV[0], 'wb') {|f|
  f.puts mkin
}
