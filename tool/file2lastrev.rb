#!/usr/bin/env ruby

# Gets the most recent revision of a file in a VCS-agnostic way.
# Used by Doxygen, Makefiles and merger.rb.

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

format = '%Y-%m-%dT%H:%M:%S%z'
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
  opts.on("--modified[=FORMAT]", "modified time") do |fmt|
    self.output = :modified
    format = fmt if fmt
  end
  opts.on("-q", "--suppress_not_found") do
    @suppress_not_found = true
  end
}
parser.parse! rescue abort "#{File.basename(Program)}: #{$!}\n#{parser}"

@output =
  case @output
  when :changed, nil
    Proc.new {|last, changed|
      changed
    }
  when :revision_h
    Proc.new {|last, changed, modified, branch, title|
      [
        "#define RUBY_REVISION #{changed || 0}",
        if branch
          e = '..'
          limit = 16
          name = branch.sub(/\A(.{#{limit-e.size}}).{#{e.size+1},}/o) {$1+e}
          "#define RUBY_BRANCH_NAME #{name.dump}"
        end,
        if title
          "#define RUBY_LAST_COMMIT_TITLE #{title.dump}"
        end,
      ].compact
    }
  when :doxygen
    Proc.new {|last, changed|
      "r#{changed}/r#{last}"
    }
  when :modified
    Proc.new {|last, changed, modified|
      modified.strftime(format)
    }
  else
    raise "unknown output format `#{@output}'"
  end

srcdir ||= File.dirname(File.dirname(Program))
begin
  vcs = VCS.detect(srcdir)
rescue VCS::NotFoundError => e
  abort "#{File.basename(Program)}: #{e.message}" unless @suppress_not_found
else
  ok = true
  (ARGV.empty? ? [nil] : ARGV).each do |arg|
    begin
      puts @output[*vcs.get_revisions(arg)]
    rescue => e
      next if @suppress_not_found and VCS::NotFoundError === e
      warn "#{File.basename(Program)}: #{e.message}"
      ok = false
    end
  end
  exit ok
end
