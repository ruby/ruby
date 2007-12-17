#! ./miniruby

dir = File.expand_path("../..", __FILE__)
$:.unshift(File.join(dir, "lib"))
$:.unshift(dir)
File.directory?("enc") || File.mkdir("enc")
$:.unshift(".")
require 'mkmf'
require 'tool/serb'

encdir = File.join($top_srcdir, "enc")

encs = Dir.open(encdir) {|d| d.grep(/.+\.c\z/)}
encs -= CONFIG["BUILTIN_ENCS"].split
encs.each {|e| e.chomp!(".c")}
mkin = File.read(File.join(encdir, "Makefile.in"))
mkin.gsub!(/^\#!\# ?/, '')
mkin.gsub!(/@(#{RbConfig::MAKEFILE_CONFIG.keys.join('|')})@/) {CONFIG[$1]}
tmp = ''
eval(serb(mkin, 'tmp'))
open(ARGV[0], 'w') {|f|
  f.puts tmp
}
