#!/bin/sh
# -*- ruby -*-
exec "${RUBY-ruby}" "-x" "$0" "$@" && [ ] if false
#!ruby
# This needs ruby 2.0, Subversion and Git.
# As a Ruby committer, run this in an SVN repository
# to commit a change.

require 'tempfile'
require 'net/http'
require 'uri'
require 'shellwords'

ENV['LC_ALL'] = 'C'
ORIGIN = 'git@git.ruby-lang.org:ruby.git'
GITHUB = 'git@github.com:ruby/ruby.git'

module Merger
  REPOS = 'svn+ssh://svn@ci.ruby-lang.org/ruby/'
end

class << Merger
  include Merger

  def help
    puts <<-HELP
\e[1msimple backport\e[0m
  ruby #$0 1234

\e[1mbackport from other branch\e[0m
  ruby #$0 17502 mvm

\e[1mrevision increment\e[0m
  ruby #$0 revisionup

\e[1mteeny increment\e[0m
  ruby #$0 teenyup

\e[1mtagging major release\e[0m
  ruby #$0 tag 2.2.0

\e[1mtagging patch release\e[0m (about 2.1.0 or later, it means X.Y.Z (Z > 0) release)
  ruby #$0 tag

\e[1mtagging preview/RC\e[0m
  ruby #$0 tag 2.2.0-preview1

\e[1mremove tag\e[0m
  ruby #$0 removetag 2.2.9

\e[33;1m* all operations shall be applied to the working directory.\e[0m
    HELP
  end

  def interactive(str, editfile = nil)
    loop do
      yield if block_given?
      STDERR.puts "\e[1;33m#{str} ([y]es|[a]bort|[r]etry#{'|[e]dit' if editfile})\e[0m"
      case STDIN.gets
      when /\Aa/i then exit
      when /\Ar/i then redo
      when /\Ay/i then break
      when /\Ae/i then system(ENV['EDITOR'], editfile)
      else exit
      end
    end
  end

  def version_up(teeny: false)
    now = Time.now
    now = now.localtime(9*60*60) # server is Japan Standard Time +09:00
    if svn_mode?
      system('svn', 'revert', 'version.h')
    else
      system('git', 'checkout', 'HEAD', 'version.h')
    end
    v, pl = version

    if teeny
      v[2].succ!
    end
    if pl != '-1' # trunk does not have patchlevel
      pl.succ!
    end

    str = open('version.h', 'rb', &:read)
    ruby_release_date = str[/RUBY_RELEASE_YEAR_STR"-"RUBY_RELEASE_MONTH_STR"-"RUBY_RELEASE_DAY_STR/] || now.strftime('"%Y-%m-%d"')
    [%W[RUBY_VERSION      "#{v.join('.')}"],
     %W[RUBY_VERSION_CODE  #{v.join('')}],
     %W[RUBY_VERSION_MAJOR #{v[0]}],
     %W[RUBY_VERSION_MINOR #{v[1]}],
     %W[RUBY_VERSION_TEENY #{v[2]}],
     %W[RUBY_RELEASE_DATE #{ruby_release_date}],
     %W[RUBY_RELEASE_CODE  #{now.strftime('%Y%m%d')}],
     %W[RUBY_PATCHLEVEL    #{pl}],
     %W[RUBY_RELEASE_YEAR  #{now.year}],
     %W[RUBY_RELEASE_MONTH #{now.month}],
     %W[RUBY_RELEASE_DAY   #{now.day}],
    ].each do |(k, i)|
      str.sub!(/^(#define\s+#{k}\s+).*$/, "\\1#{i}")
    end
    str.sub!(/\s+\z/m, '')
    fn = sprintf('version.h.tmp.%032b', rand(1 << 31))
    File.rename('version.h', fn)
    open('version.h', 'wb') do |f|
      f.puts(str)
    end
    File.unlink(fn)
  end

  def tag(relname)
    # relname:
    #   * 2.2.0-preview1
    #   * 2.2.0-rc1
    #   * 2.2.0
    v, pl = version
    if relname
      abort "patchlevel is not -1 but '#{pl}' for preview or rc" if pl != '-1' && /-(?:preview|rc)/ =~ relname
      abort "patchlevel is not 0 but '#{pl}' for the first release" if pl != '0' && /-(?:preview|rc)/ !~ relname
      pl = relname[/-(.*)\z/, 1]
      curver = "#{v.join('.')}#{("-#{pl}" if pl)}"
      if relname != curver
        abort "given relname '#{relname}' conflicts current version '#{curver}'"
      end
    else
      if pl == '-1'
        abort 'no relname is given and not in a release branch even if this is patch release'
      end
    end
    tagname = "v#{v.join('_')}#{("_#{pl}" if v[0] < "2" || (v[0] == "2" && v[1] < "1") || /^(?:preview|rc)/ =~ pl)}"

    if svn_mode?
      if relname
        branch_url = `svn info`[/URL: (.*)/, 1]
      else
        branch_url = "#{REPOS}branches/ruby_"
        if v[0] < '2' || (v[0] == '2' && v[1] < '1')
          abort 'patchlevel must be greater than 0 for patch release' if pl == '0'
          branch_url << v.join('_')
        else
          abort 'teeny must be greater than 0 for patch release' if v[2] == '0'
          branch_url << v.join('_').sub(/_\d+\z/, '')
        end
      end
      tag_url = "#{REPOS}tags/#{tagname}"
      system('svn', 'info', tag_url, out: IO::NULL, err: IO::NULL)
      if $?.success?
        abort 'specfied tag already exists. check tag name and remove it if you want to force re-tagging'
      end
      execute('svn', 'cp', '-m', "add tag #{tagname}", branch_url, tag_url, interactive: true)
    else
      unless execute('git', 'tag', tagname)
        abort 'specfied tag already exists. check tag name and remove it if you want to force re-tagging'
      end
      execute('git', 'push', ORIGIN, tagname, interactive: true)
    end
  end

  def remove_tag(relname)
    # relname:
    #   * 2.2.0-preview1
    #   * 2.2.0-rc1
    #   * 2.2.0
    #   * v2_2_0_preview1
    #   * v2_2_0_rc1
    #   * v2_2_0
    unless relname
      raise ArgumentError, 'relname is not specified'
    end
    if /^v/ !~ relname
      tagname = "v#{relname.gsub(/[.-]/, '_')}"
    else
      tagname = relname
    end

    if svn_mode?
      tag_url = "#{REPOS}tags/#{tagname}"
      execute('svn', 'rm', '-m', "remove tag #{tagname}", tag_url, interactive: true)
    else
      execute('git', 'tag', '-d', tagname)
      execute('git', 'push', ORIGIN, ":#{tagname}", interactive: true)
      execute('git', 'push', GITHUB, ":#{tagname}", interactive: true)
    end
  end

  def update_revision_h
    if svn_mode?
      execute('svn', 'up')
    end
    execute('ruby tool/file2lastrev.rb --revision.h . > revision.tmp')
    execute('tool/ifchange', '--timestamp=.revision.time', 'revision.h', 'revision.tmp')
    execute('rm', '-f', 'revision.tmp')
  end

  def stat
    if svn_mode?
      `svn stat`
    else
      `git status --short`
    end
  end

  def diff(file = nil)
    if svn_mode?
      command = %w[svn diff --diff-cmd=diff -x -upw]
    else
      command = %w[git diff --color]
    end
    IO.popen(command + [file].compact, &:read)
  end

  def commit(file)
    if svn_mode?
      begin
        execute('svn', 'ci', '-F', file)
        execute('svn', 'update') # svn ci doesn't update revision info on working copy
      ensure
        execute('rm', '-f', 'subversion.commitlog')
      end
    else
      current_branch = IO.popen(['git', 'rev-parse', '--abbrev-ref', 'HEAD'], &:read).strip
      execute('git', 'add', '.') &&
        execute('git', 'commit', '-F', file) &&
        execute('git', 'push', ORIGIN, current_branch)
    end
  end

  private

  def svn_mode?
    return @svn_mode if defined?(@svn_mode)
    @svn_mode = system("svn info", %i(out err) => IO::NULL)
  end

  # Prints the version of Ruby found in version.h
  def version
    v = p = nil
    open 'version.h', 'rb' do |f|
      f.each_line do |l|
        case l
        when /^#define RUBY_VERSION "(\d+)\.(\d+)\.(\d+)"$/
          v = $~.captures
        when /^#define RUBY_VERSION_TEENY (\d+)$/
          (v ||= [])[2] = $1
        when /^#define RUBY_PATCHLEVEL (-?\d+)$/
          p = $1
        end
      end
    end
    if v and !v[0]
      open 'include/ruby/version.h', 'rb' do |f|
        f.each_line do |l|
          case l
          when /^#define RUBY_API_VERSION_MAJOR (\d+)/
            v[0] = $1
          when /^#define RUBY_API_VERSION_MINOR (\d+)/
            v[1] = $1
          end
        end
      end
    end
    return v, p
  end

  def execute(*cmd, interactive: false)
    if interactive
      Merger.interactive("OK?: #{cmd.shelljoin}")
    end
    puts "+ #{cmd.shelljoin}"
    system(*cmd)
  end
end

case ARGV[0]
when "teenyup"
  Merger.version_up(teeny: true)
  puts Merger.diff('version.h')
when "up", /\A(ver|version|rev|revision|lv|level|patch\s*level)\s*up\z/
  Merger.version_up
  puts Merger.diff('version.h')
when "tag"
  Merger.tag(ARGV[1])
when /\A(?:remove|rm|del)_?tag\z/
  Merger.remove_tag(ARGV[1])
when nil, "-h", "--help"
  Merger.help
  exit
else
  Merger.update_revision_h

  case ARGV[0]
  when /--ticket=(.*)/
    tickets = $1.split(/,/).map{|num| " [Backport ##{num}]"}.join
    ARGV.shift
  else
    tickets = ''
  end

  revstr = ARGV[0].delete('^, :\-0-9a-fA-F')
  revs = revstr.split(/[,\s]+/)
  commit_message = ''

  revs.each do |rev|
    git_rev = nil
    case rev
    when /\A\d{1,6}\z/
      svn_rev = rev
    when /\A\h{7,40}\z/
      git_rev = rev
    when nil then
      puts "#$0 revision"
      exit
    else
      puts "invalid revision part '#{rev}' in '#{ARGV[0]}'"
      exit
    end

    # Merge revision from Git patch or SVN
    if git_rev
      git_uri = "https://git.ruby-lang.org/ruby.git/patch/?id=#{git_rev}"
      resp = Net::HTTP.get_response(URI(git_uri))
      if resp.code != '200'
        abort "'#{git_uri}' returned status '#{resp.code}':\n#{resp.body}"
      end
      patch = resp.body.sub(/^diff --git a\/version\.h b\/version\.h\nindex .*\n--- a\/version\.h\n\+\+\+ b\/version\.h\n@@ .* @@\n(?:[-\+ ].*\n|\n)+/, '')

      message = "\n\n#{(patch[/^Subject: (.*)\n\ndiff --git/m, 1] || "Message not found for revision: #{git_rev}\n")}"
      puts '+ git apply'
      IO.popen(['git', 'apply'], 'wb') { |f| f.write(patch) }
    else
      default_merge_branch = (%r{^URL: .*/branches/ruby_1_8_} =~ `svn info` ? 'branches/ruby_1_8' : 'trunk')
      svn_src = "#{Merger::REPOS}#{ARGV[1] || default_merge_branch}"
      message = IO.popen(['svn', 'log', '-c', svn_rev, svn_src], &:read)

      cmd = ['svn', 'merge', '--accept=postpone', '-c', svn_rev, svn_src]
      puts "+ #{cmd.join(' ')}"
      system(*cmd)
    end

    commit_message << message.sub(/\A-+\nr.*/, '').sub(/\n-+\n\z/, '').gsub(/^./, "\t\\&")
  end

  if Merger.diff.empty?
    Merger.interactive('Nothing is modified, right?')
  end

  Merger.version_up
  f = Tempfile.new 'merger.rb'
  f.printf "merge revision(s) %s:%s", revstr, tickets
  f.write commit_message
  f.flush
  f.close

  Merger.interactive('conflicts resolved?', f.path) do
    IO.popen(ENV['PAGER'] || ['less', '-R'], 'w') do |g|
      g << Merger.stat
      g << "\n\n"
      f.open
      g << f.read
      f.close
      g << "\n\n"
      g << Merger.diff
    end
  end

  unless Merger.commit(f.path)
    puts 'commit failed; try again.'
  end

  f.close(true)
end
