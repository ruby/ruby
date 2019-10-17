#!ruby -an
BEGIN {
  require 'fileutils'

  dir = ARGV.shift
  ARGF.eof?
  FileUtils.mkdir_p(dir)
  Dir.chdir(dir)
}

n, v, u = $F
case n
when "minitest"
  v = "master"
when "test-unit"
else
  v = "v" + v
end

if File.directory?(n)
  puts "updating #{n} ..."
  if v == "master"
    system(*%W"git pull", chdir: n) or abort
  else
    system(*%W"git fetch", chdir: n) or abort
  end
else
  puts "retrieving #{n} ..."
  system(*%W"git clone #{u} #{n}") or abort
end
system(*%W"git checkout #{v}", chdir: n) or abort
