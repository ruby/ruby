#!/usr/bin/env ruby

# Gets the most recent revision of a file in a VCS-agnostic way.
# Used by Doxygen, Makefiles and merger.rb.

require 'optparse'

# this file run with BASERUBY, which may be older than 1.9, so no
# require_relative
require File.expand_path('../lib/vcs', __FILE__)

Program = $0

@output = nil
def self.output=(output)
  if @output and @output != output
    raise "you can specify only one of --changed, --revision.h and --doxygen"
  end
  @output = output
end
@suppress_not_found = false
@limit = 20

format = '%Y-%m-%dT%H:%M:%S%z'
vcs = nil
OptionParser.new {|opts|
  opts.banner << " paths..."
  vcs_options = VCS.define_options(opts)
  new_vcs = proc do |path|
    begin
      vcs = VCS.detect(path, vcs_options, opts.new)
    rescue VCS::NotFoundError => e
      abort "#{File.basename(Program)}: #{e.message}" unless @suppress_not_found
      opts.remove
    end
    nil
  end
  opts.new
  opts.on("--srcdir=PATH", "use PATH as source directory") do |path|
    abort "#{File.basename(Program)}: srcdir is already set" if vcs
    new_vcs[path]
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
  opts.on("--limit=NUM", "limit branch name length (#@limit)", Integer) do |n|
    @limit = n
  end
  opts.on("-q", "--suppress_not_found") do
    @suppress_not_found = true
  end
  opts.order! rescue abort "#{File.basename(Program)}: #{$!}\n#{opts}"
  if vcs
    vcs.set_options(vcs_options) # options after --srcdir
  else
    new_vcs["."]
  end
}
exit unless vcs

@output =
  case @output
  when :changed, nil
    Proc.new {|last, changed|
      changed
    }
  when :revision_h
    Proc.new {|last, changed, modified, branch, title|
      short = vcs.short_revision(last)
      if /[^\x00-\x7f]/ =~ title and title.respond_to?(:force_encoding)
        title = title.dup.force_encoding("US-ASCII")
      end
      [
        "#define RUBY_REVISION #{short.inspect}",
        ("#define RUBY_FULL_REVISION #{last.inspect}" unless short == last),
        if branch
          e = '..'
          limit = @limit
          name = branch.sub(/\A(.{#{limit-e.size}}).{#{e.size+1},}/o) {$1+e}
          name = name.dump.sub(/\\#/, '#')
          "#define RUBY_BRANCH_NAME #{name}"
        end,
        if title
          title = title.dump.sub(/\\#/, '#')
          "#define RUBY_LAST_COMMIT_TITLE #{title}"
        end,
        if modified
          modified.utc.strftime('#define RUBY_RELEASE_DATETIME "%FT%TZ"')
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
