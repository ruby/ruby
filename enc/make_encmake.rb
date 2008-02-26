#! ./miniruby

dir = File.expand_path("../..", __FILE__)
$:.unshift(dir)
$:.unshift(".")
$" << "mkmf.rb"
load File.expand_path("lib/mkmf.rb", dir)
require 'erb'

if /--builtin-encs=/ =~ ARGV[0]
  BUILTIN_ENCS = $'.split.map {|e| File.basename(e, '.*') << '.c'}
  ARGV.shift
else
  BUILTIN_ENCS = []
end

if File.exist?(depend = File.join($srcdir, "depend"))
  erb = ERB.new(File.read(depend), nil, '%')
  erb.filename = depend
  tmp = erb.result(binding)
  dep = "\n#### depend ####\n\n" << depend_rules(tmp).join
else
  dep = ""
end
mkin = File.read(File.join($srcdir, "Makefile.in"))
mkin.gsub!(/@(#{CONFIG.keys.join('|')})@/) {CONFIG[$1]}
open(ARGV[0], 'wb') {|f|
  f.puts mkin, dep
}
