#!ruby -an
BEGIN {
  require 'fileutils'
  require_relative 'lib/colorize'

  color = Colorize.new

  if ARGV.first.start_with?("BUNDLED_GEMS=")
    bundled_gems = ARGV.shift[13..-1]
    sep = bundled_gems.include?(",") ? "," : " "
    bundled_gems = bundled_gems.split(sep)
    bundled_gems = nil if bundled_gems.empty?
  end

  dir = ARGV.shift
  ARGF.eof?
  FileUtils.mkdir_p(dir)
  Dir.chdir(dir)
}

n, v, u, r = $F

next unless n
next if n =~ /^#/
next if bundled_gems&.all? {|pat| !File.fnmatch?(pat, n)}

if File.directory?(n)
  puts "updating #{color.notice(n)} ..."
  system("git", "fetch", "--all", chdir: n) or abort
else
  puts "retrieving #{color.notice(n)} ..."
  system(*%W"git clone #{u} #{n}") or abort
end

if r
  puts "fetching #{color.notice(r)} ..."
  system("git", "fetch", "origin", r, chdir: n) or abort
end

c = r || "v#{v}"
checkout = %w"git -c advice.detachedHead=false checkout"
print %[checking out #{color.notice(c)} (v=#{color.info(v)}]
print %[, r=#{color.info(r)}] if r
puts ") ..."
unless system(*checkout, c, "--", chdir: n)
  abort if r or !system(*checkout, v, "--", chdir: n)
end

if r
  unless File.exist? "#{n}/#{n}.gemspec"
    require_relative "lib/bundled_gem"
    BundledGem.dummy_gemspec("#{n}/#{n}.gemspec")
  end
end
