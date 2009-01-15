#!/usr/bin/env ruby

ENV.delete('PWD')

require 'optparse'
require 'pathname'

SRCDIR = Pathname(File.dirname($0)).parent.freeze
class VCSNotFoundError < RuntimeError; end

def detect_vcs(path)
  path = SRCDIR
  return :svn, path.relative_path_from(SRCDIR) if File.directory?("#{path}/.svn")
  return :git_svn, path.relative_path_from(SRCDIR) if File.directory?("#{path}/.git/svn")
  return :git, path.relative_path_from(SRCDIR) if File.directory?("#{path}/.git")
  raise VCSNotFoundError, "does not seem to be under a vcs"
end

# return a pair of strings, the last revision and the last revision in which
# +path+ was modified.
def get_revisions(path)
  vcs, path = detect_vcs(path)

  info = case vcs
  when :svn
    info_xml = `cd "#{SRCDIR}" && svn info --xml "#{path}"`
    _, last, _, changed, _ = info_xml.split(/revision="(\d+)"/)
    return last, changed
  when :git_svn
    `cd "#{SRCDIR}" && git svn info "#{path}"`
  when :git
    git_log = `cd "#{SRCDIR}" && git log HEAD~1..HEAD "#{path}"`
    git_log =~ /git-svn-id: .*?@(\d+)/
    return $1, $1
  end

  if /^Revision: (\d+)/ =~ info
    last = $1 
  else
    raise "last revision not found"
  end
  if /^Last Changed Rev: (\d+)/ =~ info
    changed = $1
  else
    raise "changed revision not found"
  end

  return last, changed
end

def raise_if_conflict
  raise "you can specify only one of --changed, --revision.h and --doxygen" if $output
end

parser = OptionParser.new {|opts|
  opts.on("--changed", "changed rev") do
    raise_if_conflict
    $output = :changed
  end
  opts.on("--revision.h") do
    raise_if_conflict
    $output = :revision_h
  end
  opts.on("--doxygen") do
    raise_if_conflict
    $output = :doxygen
  end
  opts.on("-q", "--suppress_not_found") do
    $suppress_not_found = true
  end
}
parser.parse!


begin
  last, changed = get_revisions(ARGV.shift)
rescue VCSNotFoundError
  raise unless $suppress_not_found
end

case $output
when :changed, nil
  puts changed
when :revision_h
  puts "#define RUBY_REVISION #{changed.to_i}"
when :doxygen
  puts "r#{changed}/r#{last}"
else
  raise "unknown output format `#{$output}'"
end
