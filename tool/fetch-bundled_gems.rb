#!ruby -alnF\s+|#.*
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
next if bundled_gems&.all? {|pat| !File.fnmatch?(pat, n)}

unless File.exist?("#{n}/.git")
  puts "retrieving #{color.notice(n)} ..."
  cloned = (1..3).any? do |retry_count|
    system(*%W"git clone --depth=1 --no-tags #{u} #{n}") or begin
      warn "Clone failed (attempt #{retry_count}/3)#{retry_count < 3 ? ", retrying..." : ", giving up."}"
      FileUtils.rm_rf(n) if File.exist?(n)
      sleep(retry_count * 5) if retry_count < 3
      false
    end
  end
  abort unless cloned
end

candidates = r ? [r] : ["v#{v}", v]

# Skip fetching from the remote when the target ref already exists locally
# (e.g. restored from cache), so a transient network failure does not abort.
c = candidates.find do |c|
  system("git", "rev-parse", "-q", "--verify", "#{c}^{commit}", out: File::NULL, err: File::NULL, chdir: n)
end

c ||= candidates.find do |c|
  puts "fetching #{n} #{color.notice(c)} ..."
  system("git", "fetch", "origin", r || "refs/tags/#{c}:refs/tags/#{c}", chdir: n)
end or abort

checkout = %w"git -c advice.detachedHead=false checkout"
info = %[, r=#{color.info(r)}] if r
puts "checking out #{color.notice(c)} (v=#{color.info(v)}#{info}) ..."
unless system(*checkout, c, "--", chdir: n)
  abort if r or !system(*checkout, v, "--", chdir: n)
end

if r
  unless File.exist? "#{n}/#{n}.gemspec"
    require_relative "lib/bundled_gem"
    BundledGem.dummy_gemspec("#{n}/#{n}.gemspec")
  end
end
