#!/usr/bin/env ruby

# Gets the most recent revision of a file in a VCS-agnostic way.
# Used by Doxygen, Makefiles and merger.rb.

require 'optparse'

# this file run with BASERUBY, which may be older than 1.9, so no
# require_relative
require File.expand_path('../lib/vcs', __FILE__)
require File.expand_path('../lib/output', __FILE__)

Program = $0

@format = nil
def self.format=(format)
  if @format and @format != format
    raise "you can specify only one of --changed, --revision.h and --doxygen"
  end
  @format = format
end
@suppress_not_found = false
@limit = 20
@output = Output.new

time_format = '%Y-%m-%dT%H:%M:%S%z'
vcs = nil
create_only = false
OptionParser.new {|opts|
  opts.banner << " paths..."
  vcs_options = VCS.define_options(opts)
  opts.new {@output.def_options(opts)}
  srcdir = nil
  opts.new
  opts.on("--srcdir=PATH", "use PATH as source directory") do |path|
    abort "#{File.basename(Program)}: srcdir is already set" if srcdir
    srcdir = path
    @output.vpath.add(srcdir)
  end
  opts.on("--changed", "changed rev") do
    self.format = :changed
  end
  opts.on("--revision.h", "RUBY_REVISION macro") do
    self.format = :revision_h
  end
  opts.on("--doxygen", "Doxygen format") do
    self.format = :doxygen
  end
  opts.on("--modified[=FORMAT]", "modified time") do |fmt|
    self.format = :modified
    time_format = fmt if fmt
  end
  opts.on("--limit=NUM", "limit branch name length (#@limit)", Integer) do |n|
    @limit = n
  end
  opts.on("-q", "--suppress_not_found") do
    @suppress_not_found = true
  end
  opts.order! rescue abort "#{File.basename(Program)}: #{$!}\n#{opts}"
  begin
    vcs = VCS.detect(srcdir || ".", vcs_options, opts.new)
  rescue VCS::NotFoundError => e
    abort "#{File.basename(Program)}: #{e.message}" unless @suppress_not_found
    opts.remove
    (vcs = VCS::Null.new(nil)).set_options(vcs_options)
    if @format == :revision_h
      create_only = true # don't overwrite existing revision.h when .git doesn't exist
    end
  end
}

formatter =
  case @format
  when :changed, nil
    Proc.new {|last, changed|
      changed || ""
    }
  when :revision_h
    Proc.new {|last, changed, modified, branch, title|
      vcs.revision_header(last, modified, modified, branch, title, limit: @limit).join("\n")
    }
  when :doxygen
    Proc.new {|last, changed|
      "r#{changed}/r#{last}"
    }
  when :modified
    Proc.new {|last, changed, modified|
      modified.strftime(time_format)
    }
  else
    raise "unknown output format `#{@format}'"
  end

ok = true
(ARGV.empty? ? [nil] : ARGV).each do |arg|
  begin
    data = formatter[*vcs.get_revisions(arg)]
    data.sub!(/(?<!\A|\n)\z/, "\n")
    @output.write(data, overwrite: true, create_only: create_only)
  rescue => e
    warn "#{File.basename(Program)}: #{e.message}"
    ok = false
  end
end
exit ok
