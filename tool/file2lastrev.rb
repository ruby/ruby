#!/usr/bin/env ruby

ENV.delete('PWD')

require 'optparse'
require 'pathname'

Program = Pathname($0)

class VCS
  class NotFoundError < RuntimeError; end

  @@dirs = []
  def self.register(dir)
    @@dirs << [dir, self]
  end

  def self.detect(path)
    @@dirs.sort.reverse_each do |dir, klass|
      return klass.new(path) if File.directory?("#{path}/#{dir}")
    end
    raise VCS::NotFoundError, "does not seem to be under a vcs: #{path}"
  end

  def initialize(path)
    @srcdir = path
    super()
  end

  # return a pair of strings, the last revision and the last revision in which
  # +path+ was modified.
  def get_revisions(path)
    path = relative_to(path)
    last, changed, *rest = Dir.chdir(@srcdir) {self.class.get_revisions(path)}
    last or raise "last revision not found"
    changed or raise "changed revision not found"
    return last, changed, *rest
  end

  def relative_to(path)
    path ? Pathname(path).relative_path_from(@srcdir) : '.'
  end

  class SVN < self
    register(".svn")

    def self.get_revisions(path)
      info_xml = `svn info --xml "#{path}"`
      _, last, _, changed, _ = info_xml.split(/revision="(\d+)"/)
      [last, changed]
    end
  end

  class GIT_SVN < self
    register(".git/svn")

    def self.get_revisions(path)
      lastlog = `git log -n1`
      info = `git svn info "#{path}"`
      [info[/^Revision: (\d+)/, 1], info[/^Last Changed Rev: (\d+)/, 1]]
    end
  end

  class GIT < self
    register(".git")

    def self.get_revisions(path)
      logcmd = %Q[git log -n1 --grep="^ *git-svn-id: .*@[0-9][0-9]* "]
      idpat = /git-svn-id: .*?@(\d+) \S+\Z/
      last = `#{logcmd}`[idpat, 1]
      changed = path ? `#{logcmd} "#{path}"`[idpat, 1] : last
      [last, changed]
    end
  end
end

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
  opts.on("-q", "--suppress_not_found") do
    @suppress_not_found = true
  end
}
parser.parse! rescue abort "#{Program.basename}: #{$!}\n#{parser}"

srcdir = (srcdir ? Pathname(srcdir) : Program.parent.parent).freeze
begin
  vcs = VCS.detect(srcdir)
rescue VCS::NotFoundError => e
  abort "#{Program.basename}: #{e.message}" unless @suppress_not_found
else
  last, changed = vcs.get_revisions(ARGV.shift)
end

case @output
when :changed, nil
  puts changed
when :revision_h
  puts "#define RUBY_REVISION #{changed.to_i}"
when :doxygen
  puts "r#{changed}/r#{last}"
else
  raise "unknown output format `#{@output}'"
end
