#!ruby -an
BEGIN {
  require 'fileutils'

  dir = ARGV.shift
  ARGF.eof?
  FileUtils.mkdir_p(dir)
  Dir.chdir(dir)
}

n, v, u, r = $F

next unless n
next if n =~ /^#/

if File.directory?(n)
  puts "updating #{n} ..."
  system("git", "fetch", chdir: n) or abort
else
  puts "retrieving #{n} ..."
  system(*%W"git clone #{u} #{n}") or abort
end
if r
  puts "fetching #{r} ..."
  system("git", "fetch", "origin", r, chdir: n) or abort

  unless File.exist? "#{n}/#{n}.gemspec"
    require_relative "lib/bundled_gem"
    BundledGem.dummy_gemspec("#{n}/#{n}.gemspec")
  end

  # Check bundled_gems version and gemspec version same as BundledGem.build
  spec = Gem::Specification.load("#{n}/#{n}.gemspec")
  abort "Unexpected version #{spec.version}" unless spec.version == Gem::Version.new(v)
end
c = r || "v#{v}"
checkout = %w"git -c advice.detachedHead=false checkout"
puts "checking out #{c} (v=#{v}, r=#{r}) ..."
unless system(*checkout, c, "--", chdir: n)
  abort if r or !system(*checkout, v, "--", chdir: n)
end
