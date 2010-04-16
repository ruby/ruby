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
    if path
      path = Pathname(path)
      srcdir = @srcdir
      if path.absolute? ^ srcdir.absolute?
        if path.absolute?
          srcdir = srcdir.expand_path
        end
      else
        if srcdir.absolute?
          path = path.expand_path
        end
      end
      path.relative_path_from(srcdir)
    else
      '.'
    end
  end

  class SVN < self
    register(".svn")

    def self.get_revisions(path)
      begin
        nulldevice = %w[/dev/null NUL NIL: NL:].find {|dev| File.exist?(dev)}
        if nulldevice
          save_stderr = STDERR.dup
          STDERR.reopen nulldevice, 'w'
        end
        info_xml = `svn info --xml "#{path}"`
      ensure
        if save_stderr
          STDERR.reopen save_stderr
          save_stderr.close
        end
      end
      _, last, _, changed, _ = info_xml.split(/revision="(\d+)"/)
      [last, changed]
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
  begin
    last, changed = vcs.get_revisions(ARGV.shift)
  rescue => e
    abort "#{Program.basename}: #{e.message}" unless @suppress_not_found
    exit false
  end
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
