#!/usr/bin/env ruby

require 'optparse'

# this file run with BASERUBY, which may be older than 1.9, so no
# require_relative
require File.expand_path('../vcs', __FILE__)

Program = $0

@output = nil
def self.output=(output)
  if @output and @output != output
    raise "you can specify only one of --changed, --revision.h and --doxygen"
  end
  @output = output
end
@suppress_not_found = false

srcdir = nil
parser = OptionParser.new {|opts|
  opts.on("--srcdir=PATH", "use PATH as source directory") do |path|
    srcdir = path
  end
  opts.on("--changed", "changed rev") do
    self.output = :changed
  end
  opts.on("--revision.h", "RUBY_REVISION macro") do
    self.output = :revision_h
  end
  opts.on("--doxygen", "Doxygen format") do
    self.output = :doxygen
  end
  opts.on("--modified", "modified time") do
    self.output = :modified
  end
  opts.on("-q", "--suppress_not_found") do
    @suppress_not_found = true
  end
}
parser.parse! rescue abort "#{File.basename(Program)}: #{$!}\n#{parser}"

srcdir ||= File.dirname(File.dirname(Program))
begin
  vcs = VCS.detect(srcdir)
rescue VCS::NotFoundError => e
  abort "#{File.basename(Program)}: #{e.message}" unless @suppress_not_found
else
  begin
    last, changed, modified, branch, title = vcs.get_revisions(ARGV.shift)
  rescue => e
    abort "#{File.basename(Program)}: #{e.message}" unless @suppress_not_found
    exit false
  end
end

case @output
when :changed, nil
  puts changed
when :revision_h
  puts "#define RUBY_REVISION #{changed || 0}"
  if branch
    e = '..'
    limit = 16
    name = branch.sub(/\A(.{#{limit-e.size}}).{#{e.size+1},}/o) {$1+e}
    puts "#define RUBY_BRANCH_NAME #{name.dump}"
  end
  if title
    puts "#define RUBY_LAST_COMMIT_TITLE #{title.dump}"
  end
when :doxygen
  puts "r#{changed}/r#{last}"
when :modified
  puts modified.strftime('%Y-%m-%dT%H:%M:%S%z')
else
  raise "unknown output format `#{@output}'"
end
