#!/usr/bin/env ruby

require 'optparse'
require 'pathname'

class VCSNotFoundError < RuntimeError; end

def detect_vcs(path)
  target_path = Pathname(File.expand_path(path))

  path = target_path.directory? ? target_path : target_path.parent  
  begin
    return :svn, target_path.relative_path_from(path) if File.directory?("#{path}/.svn")
    return :git, target_path.relative_path_from(path) if File.directory?("#{path}/.git")
    path, orig = path.parent, path
  end until path == orig
  raise VCSNotFoundError, "does not seem to be under a vcs"
end

def get_revisions(path)
  ENV['LANG'] = ENV['LC_ALL'] = ENV['LC_MESSAGES'] = 'C'
  vcs, path = detect_vcs(path)

  info = case vcs
  when :svn
    `svn info #{path}`
  when :git
    `git svn info #{path}`
  end

  if info =~ /^Revision: (\d+)$/
    last = $1 
  else
    raise "last revision not found"
  end
  if info =~ /^Last Changed Rev: (\d+)$/
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
  puts "#define RUBY_REVISION #{changed}"
when :doxygen
  puts "r#{changed}/r#{last}"
else
  raise "unknown output format `#{$output}'"
end
