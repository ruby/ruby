#!/bin/sh
# -*- ruby -*-
exec "${RUBY-ruby}" "-x" "$0" "$@" && [ ] if false
#!ruby
# This needs ruby 1.9 and subversion.
# As a Ruby committer, run this in an SVN repository
# to commit a change.

require 'fileutils'
require 'tempfile'

$repos = 'svn+ssh://svn@ci.ruby-lang.org/ruby/'
ENV['LC_ALL'] = 'C'

def help
  puts <<-end
\e[1msimple backport\e[0m
  ruby #$0 1234

\e[1mrange backport\e[0m
  ruby #$0 1234:5678

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
      when /^#define RUBY_PATCHLEVEL (-?\d+)$/
        p = $1
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
  [%W[RUBY_VERSION      "#{v.join '.'}"],
   %W[RUBY_VERSION_CODE  #{v.join ''}],
   %W[RUBY_VERSION_MAJOR #{v[0]}],
   %W[RUBY_VERSION_MINOR #{v[1]}],
   %W[RUBY_VERSION_TEENY #{v[2]}],
   %W[RUBY_RELEASE_DATE "#{d.strftime '%Y-%m-%d'}"],
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
  if intv_p
    interactive "OK? svn cp -m \"add tag #{tagname}\" #{branch_url} #{tag_url}" do
    end
  end
  system(*%w'svn cp -m', "add tag #{tagname}", branch_url, tag_url)
  puts "run following command in git-svn working directory to push the tag into GitHub:"
  puts "git tag #{tagname}  origin/tags/#{tagname} && git push ruby #{tagname}"
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
  when /merge revision\(s\) ([\d,\-]+):( \[.*)/
    tickets = $2
    ARGV[0] = $1
  else
    tickets = ''
  end

  q = $repos + (ARGV[1] || default_merge_branch)
  revstr = ARGV[0].delete('^, :\-0-9')
  revs = revstr.split(/[,\s]+/)
  log = ''
  log_svn = ''

  revs.each do |rev|
    case rev
    when /\A\d+:\d+\z/
      r = ['-r', rev]
    when /\A(\d+)-(\d+)\z/
      rev = "#{$1.to_i-1}:#$2"
      r = ['-r', rev]
    when /\A\d+\z/
      r = ['-c', rev]
    when nil then
      puts "#$0 revision"
      exit
    else
      puts "invalid revision part '#{rev}' in '#{ARGV[0]}'"
      exit
    end

    l = IO.popen %w'svn diff' + r + %w'--diff-cmd=diff -x -pU0' + [File.join(q, 'ChangeLog')] do |f|
      f.read
    end

    log << l
    l = l.lines.grep(/^\+\t/).join.gsub(/^\+/, '').gsub(/^\t\*/, "\n\t\*")

    if l.empty?
      l = IO.popen %w'svn log ' + r + [q] do |f|
        f.read
      end.sub(/\A-+\nr.*/, '').sub(/\n-+\n\z/, '').gsub(/^./, "\t\\&")
    end
    log_svn << l

    a = %w'svn merge --accept=postpone' + r + [q]
    STDERR.puts a.join(' ')

    system(*a)
    system(*%w'svn revert ChangeLog') if /^\+/ =~ l
  end

  if `svn diff --diff-cmd=diff -x -upw`.empty?
    interactive 'Only ChangeLog is modified, right?' do
    end
  end

  if /^\+/ =~ log
    system(*%w'svn revert ChangeLog')
    IO.popen %w'patch -p0', 'wb' do |f|
      f.write log.gsub(/\+(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [ 123][0-9] [012][0-9]:[0-5][0-9]:[0-5][0-9] \d\d\d\d/,
                       # this format-time-string was from the file local variables of ChangeLog
                       '+'+Time.now.strftime('%a %b %e %H:%M:%S %Y'))
    end
    system(*%w'touch ChangeLog') # needed somehow, don't know why...
  else
    STDERR.puts '*** You should write ChangeLog NOW!!! ***'
  end

  version_up
  f = Tempfile.new 'merger.rb'
  f.printf "merge revision(s) %s:%s", revstr, tickets
  f.write log_svn
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
