#!ruby -an
BEGIN {
  require 'fileutils'

  dir = ARGV.shift
  ARGF.eof?
  FileUtils.mkdir_p(dir)
  Dir.chdir(dir)
}

n, v, u, r = $F

next if n =~ /^#/

if File.directory?(n)
  puts "updating #{n} ..."
  system("git", "fetch", chdir: n) or abort
else
  puts "retrieving #{n} ..."
  system(*%W"git clone #{u} #{n}") or abort
end
c = r || "v#{v}"
checkout = %w"git -c advice.detachedHead=false checkout"
puts "checking out #{c} (v=#{v}, r=#{r}) ..."
unless system(*checkout, c, "--", chdir: n)
  abort
end
