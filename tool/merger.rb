#!/bin/sh
# -*- ruby -*-
exec "${RUBY-ruby}" "-x" "$0" "$@" && [ ] if false
#!ruby
# This needs ruby 1.9 and subversion.
# As a Ruby committer, run this in an SVN repository
# to commit a change.

require 'fileutils'
require 'tempfile'
require 'net/http'
require 'uri'

$repos = 'svn+ssh://svn@ci.ruby-lang.org/ruby/'
ENV['LC_ALL'] = 'C'

def help
  puts <<-end
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
end
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

def interactive str, editfile = nil
  loop do
    yield
    STDERR.puts "\e[1;33m#{str} ([y]es|[a]bort|[r]etry#{'|[e]dit' if editfile})\e[0m"
    case STDIN.gets
    when /\Aa/i then exit
    when /\Ar/i then redo
    when /\Ay/i then break
    when /\Ae/i then system(ENV["EDITOR"], editfile)
    else exit
    end
  end
end

def version_up(inc=nil)
  d = Time.now
  d = d.localtime(9*60*60) # server is Japan Standard Time +09:00
  system(*%w'svn revert version.h')
  v, pl = version

  if inc == :teeny
    v[2].succ!
  end
  # patchlevel
  if pl != "-1"
    pl.succ!
  end

  str = open 'version.h', 'rb' do |f| f.read end
  ruby_release_date = str[/RUBY_RELEASE_YEAR_STR"-"RUBY_RELEASE_MONTH_STR"-"RUBY_RELEASE_DAY_STR/] || d.strftime('"%Y-%m-%d"')
  [%W[RUBY_VERSION      "#{v.join '.'}"],
   %W[RUBY_VERSION_CODE  #{v.join ''}],
   %W[RUBY_VERSION_MAJOR #{v[0]}],
   %W[RUBY_VERSION_MINOR #{v[1]}],
   %W[RUBY_VERSION_TEENY #{v[2]}],
   %W[RUBY_RELEASE_DATE #{ruby_release_date}],
   %W[RUBY_RELEASE_CODE  #{d.strftime '%Y%m%d'}],
   %W[RUBY_PATCHLEVEL    #{pl}],
   %W[RUBY_RELEASE_YEAR  #{d.year}],
   %W[RUBY_RELEASE_MONTH #{d.month}],
   %W[RUBY_RELEASE_DAY   #{d.day}],
  ].each do |(k, i)|
    str.sub!(/^(#define\s+#{k}\s+).*$/, "\\1#{i}")
  end
  str.sub!(/\s+\z/m, '')
  fn = sprintf 'version.h.tmp.%032b', rand(1 << 31)
  File.rename 'version.h', fn
  open 'version.h', 'wb' do |f|
    f.puts str
  end
  File.unlink fn
end

def tag intv_p = false, relname=nil
  # relname:
  #   * 2.2.0-preview1
  #   * 2.2.0-rc1
  #   * 2.2.0
  v, pl = version
  x = v.join('_')
  if relname
    abort "patchlevel is not -1 but '#{pl}' for preview or rc" if pl != '-1' && /-(?:preview|rc)/ =~ relname
    abort "patchlevel is not 0 but '#{pl}' for the first release" if pl != '0' && /-(?:preview|rc)/ !~ relname
    pl = relname[/-(.*)\z/, 1]
    curver = v.join('.') + (pl ? '-' + pl : '')
    if relname != curver
      abort "given relname '#{relname}' conflicts current version '#{curver}'"
    end
    branch_url = `svn info`[/URL: (.*)/, 1]
  else
    if pl == '-1'
      abort "no relname is given and not in a release branch even if this is patch release"
    end
    branch_url = $repos + 'branches/ruby_'
    if v[0] < "2" || (v[0] == "2" && v[1] < "1")
      abort "patchlevel must be greater than 0 for patch release" if pl == "0"
      branch_url << x
    else
      abort "teeny must be greater than 0 for patch release" if v[2] == "0"
      branch_url << x.sub(/_\d+$/, '')
    end
  end
  tagname = 'v' + x + (v[0] < "2" || (v[0] == "2" && v[1] < "1") || /^(?:preview|rc)/ =~ pl ? '_' + pl : '')
  tag_url = $repos + 'tags/' + tagname
  system(*%w'svn info', tag_url, out: IO::NULL, err: IO::NULL)
  if $?.success?
    abort "specfied tag already exists. check tag name and remove it if you want to force re-tagging"
  end
  if intv_p
    interactive "OK? svn cp -m \"add tag #{tagname}\" #{branch_url} #{tag_url}" do
      # nothing to do here
    end
  end
  system(*%w'svn cp -m', "add tag #{tagname}", branch_url, tag_url)
end

def remove_tag intv_p = false, relname
  # relname:
  #   * 2.2.0-preview1
  #   * 2.2.0-rc1
  #   * 2.2.0
  #   * v2_2_0_preview1
  #   * v2_2_0_rc1
  #   * v2_2_0
  if !relname && !intv_p.is_a?(String)
    raise ArgumentError, "relname is not specified"
  end
  intv_p, relname = false, intv_p if !relname && intv_p.is_a?(String)

  if /^v/ !~ relname
    tagname = 'v' + relname.tr(".-", "_")
  else
    tagname = relname
  end
  tag_url = $repos + 'tags/' + tagname
  if intv_p
    interactive "OK? svn rm -m \"remove tag #{tagname}\" #{tag_url}" do
      # nothing to do here
    end
  end
  system(*%w'svn rm -m', "remove tag #{tagname}", tag_url)
end

def default_merge_branch
  %r{^URL: .*/branches/ruby_1_8_} =~ `svn info` ? 'branches/ruby_1_8' : 'trunk'
end

case ARGV[0]
when "teenyup"
  version_up(:teeny)
  system 'svn diff version.h'
when "up", /\A(ver|version|rev|revision|lv|level|patch\s*level)\s*up/
  version_up
  system 'svn diff version.h'
when "tag"
  tag :interactive, ARGV[1]
when /\A(?:remove|rm|del)_?tag\z/
  remove_tag :interactive, ARGV[1]
when nil, "-h", "--help"
  help
  exit
else
  system 'svn up'
  system 'ruby tool/file2lastrev.rb --revision.h . > revision.tmp'
  system 'tool/ifchange "--timestamp=.revision.time" "revision.h" "revision.tmp"'
  FileUtils.rm_f('revision.tmp')

  case ARGV[0]
  when /--ticket=(.*)/
    tickets = $1.split(/,/).map{|num| " [Backport ##{num}]"}.join
    ARGV.shift
  else
    tickets = ''
  end

  q = $repos + (ARGV[1] || default_merge_branch)
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
      patch = resp.body

      message = "\n\n#{(patch.match(/^Subject: (.*)\n\ndiff --git/m)&.[](1) || "Message not found for revision: #{git_rev}\n")}"
      puts "+ git apply"
      IO.popen(['git', 'apply'], 'w') { |f| f.write(patch) }
    else
      message = IO.popen(['svn', 'log', '-r', svn_rev, q], &:read)

      cmd = ['svn', 'merge', '--accept=postpone', '-r', svn_rev, q]
      puts "+ #{cmd.join(' ')}"
      system(*cmd)
    end

    commit_message << message.sub(/\A-+\nr.*/, '').sub(/\n-+\n\z/, '').gsub(/^./, "\t\\&")
  end

  if `svn diff --diff-cmd=diff -x -upw`.empty?
    interactive 'Nothing is modified, right?' do
    end
  end

  version_up
  f = Tempfile.new 'merger.rb'
  f.printf "merge revision(s) %s:%s", revstr, tickets
  f.write commit_message
  f.flush
  f.close

  interactive 'conflicts resolved?', f.path do
    IO.popen(ENV["PAGER"] || "less", "w") do |g|
      g << `svn stat`
      g << "\n\n"
      f.open
      g << f.read
      f.close
      g << "\n\n"
      g << `svn diff --diff-cmd=diff -x -upw`
    end
  end

  if system(*%w'svn ci -F', f.path)
    # tag :interactive # no longer needed.
    system 'rm -f subversion.commitlog'
  else
    puts 'commit failed; try again.'
  end

  f.close(true)
end
