#!/usr/bin/env ruby
# Usage:
#   auto-style.rb [oldrev] [newrev] [pushref]

require 'shellwords'
require 'tmpdir'
ENV['LC_ALL'] = 'C'

class Git
  attr_reader :depth

  def initialize(oldrev, newrev, branch = nil)
    @oldrev = oldrev
    @newrev = newrev
    @branch = branch

    # GitHub may not fetch github.event.pull_request.base.sha at checkout
    git('log', '--format=%H', '-1', @oldrev, out: IO::NULL, err: [:child, :out]) or
      git('fetch', '--depth=1', 'origin', @oldrev)
    git('log', '--format=%H', '-1', "#@newrev~99", out: IO::NULL, err: [:child, :out]) or
      git('fetch', '--depth=100', 'origin', @newrev)

    with_clean_env do
      @revs = {}
      IO.popen(['git', 'log', '--format=%H %s', "#{@oldrev}..#{@newrev}"]) do |f|
        f.each do |line|
          line.chomp!
          rev, subj = line.split(' ', 2)
          @revs[rev] = subj
        end
      end
      @depth = @revs.size
    end
  end

  # ["foo/bar.c", "baz.h", ...]
  def updated_paths
    with_clean_env do
      IO.popen(['git', 'diff', '--name-only', @oldrev, @newrev], &:readlines).each(&:chomp!)
    end
  end

  # [0, 1, 4, ...]
  def updated_lines(file) # NOTE: This doesn't work well on pull requests, so not used anymore
    lines = []
    revs = @revs.map {|rev, subj| rev unless subj.start_with?("Revert ")}.compact
    revs_pattern = /\A(?:#{revs.join('|')}) /
    with_clean_env { IO.popen(['git', 'blame', '-l', '--', file], &:readlines) }.each_with_index do |line, index|
      if revs_pattern =~ line
        lines << index
      end
    end
    lines
  end

  def commit(log, *files)
    git('add', *files)
    git('commit', '-m', log)
  end

  def push
    git('push', 'origin', @branch)
  end

  def diff
    git('--no-pager', 'diff')
  end

  private

  def git(*args, **opts)
    cmd = ['git', *args].shelljoin
    puts "+ #{cmd}"
    ret = with_clean_env { system('git', *args, **opts) }
    unless ret or opts[:err]
      abort "Failed to run: #{cmd}"
    end
    ret
  end

  def with_clean_env
    git_dir = ENV.delete('GIT_DIR') # this overcomes '-C' or pwd
    yield
  ensure
    ENV['GIT_DIR'] = git_dir if git_dir
  end
end

DEFAULT_GEM_LIBS = %w[
  bundler
  cmath
  csv
  e2mmap
  fileutils
  forwardable
  ipaddr
  irb
  logger
  matrix
  mutex_m
  ostruct
  prime
  rdoc
  rexml
  rss
  scanf
  shell
  sync
  thwait
  tracer
  webrick
]

DEFAULT_GEM_EXTS = %w[
  bigdecimal
  date
  dbm
  digest
  etc
  fcntl
  fiddle
  gdbm
  io/console
  io/nonblock
  json
  openssl
  psych
  racc
  sdbm
  stringio
  strscan
  zlib
]

IGNORED_FILES = [
  # default gems whose master is GitHub
  %r{\Abin/(?!erb)\w+\z},
  *(DEFAULT_GEM_LIBS + DEFAULT_GEM_EXTS).flat_map { |lib|
    [
      %r{\Alib/#{lib}/},
      %r{\Alib/#{lib}\.gemspec\z},
      %r{\Alib/#{lib}\.rb\z},
      %r{\Atest/#{lib}/},
    ]
  },
  *DEFAULT_GEM_EXTS.flat_map { |ext|
    [
      %r{\Aext/#{ext}/},
      %r{\Atest/#{ext}/},
    ]
  },

  # vendoring (ccan)
  %r{\Accan/},

  # vendoring (io/)
  %r{\Aext/io/},

  # vendoring (nkf)
  %r{\Aext/nkf/nkf-utf8/},

  # vendoring (onigmo)
  %r{\Aenc/},
  %r{\Ainclude/ruby/onigmo\.h\z},
  %r{\Areg.+\.(c|h)\z},

  # explicit or implicit `c-file-style: "linux"`
  %r{\Aaddr2line\.c\z},
  %r{\Amissing/},
  %r{\Astrftime\.c\z},
  %r{\Avsnprintf\.c\z},

  # to respect the original statements of licenses
  %r{\ALEGAL\z},

  # trailing spaces could be intentional in TRICK code
  %r{\Asample/trick[^/]*/},
]

DIFFERENT_STYLE_FILES = %w[
  addr2line.c io_buffer.c prism*.c scheduler.c
]

oldrev, newrev, pushref = ARGV
unless dry_run = pushref.empty?
  branch = IO.popen(['git', 'rev-parse', '--symbolic', '--abbrev-ref', pushref], &:read).strip
end
git = Git.new(oldrev, newrev, branch)

updated_files = git.updated_paths
files = updated_files.select {|l|
  /^\d/ !~ l and /\.bat\z/ !~ l and
  (/\A(?:config|[Mm]akefile|GNUmakefile|README)/ =~ File.basename(l) or
   /\A\z|\.(?:[chsy]|\d+|e?rb|tmpl|bas[eh]|z?sh|in|ma?k|def|src|trans|rdoc|ja|en|el|sed|awk|p[ly]|scm|mspec|html|)\z/ =~ File.extname(l))
}
files.select! {|n| File.file?(n) }
files.reject! do |f|
  IGNORED_FILES.any? { |re| f.match(re) }
end
if files.empty?
  puts "No files are an auto-style target:\n#{updated_files.join("\n")}"
  exit
end

trailing = eofnewline = expandtab = indent = false

edited_files = files.select do |f|
  src = File.binread(f) rescue next
  eofnewline = eofnewline0 = true if src.sub!(/(?<!\A|\n)\z/, "\n")

  trailing0 = false
  expandtab0 = false
  indent0 = false

  src.gsub!(/^.*$/).with_index do |line, lineno|
    trailing = trailing0 = true if line.sub!(/[ \t]+$/, '')
    line
  end

  if f.end_with?('.c') || f.end_with?('.h') || f == 'insns.def'
    # If and only if unedited lines did not have tab indentation, prevent introducing tab indentation to the file.
    expandtab_allowed = src.each_line.with_index.all? do |line, lineno|
      !line.start_with?("\t")
    end

    if expandtab_allowed
      src.gsub!(/^.*$/).with_index do |line, lineno|
        if line.start_with?("\t") # last-committed line with hard tabs
          expandtab = expandtab0 = true
          line.sub(/\A\t+/) { |tabs| ' ' * (8 * tabs.length) }
        else
          line
        end
      end
    end
  end

  if File.fnmatch?("*.[ch]", f, File::FNM_PATHNAME) &&
     !DIFFERENT_STYLE_FILES.any? {|pat| File.fnmatch?(pat, f, File::FNM_PATHNAME)}
    indent0 = true if src.gsub!(/^\w+\([^\n]*?\)\K[ \t]*(?=\{( *\\)?$)/, '\1' "\n")
    indent0 = true if src.gsub!(/^([ \t]*)\}\K[ \t]*(?=else\b.*?( *\\)?$)/, '\2' "\n" '\1')
    indent0 = true if src.gsub!(/^[ \t]*\}\n\K\n+(?=[ \t]*else\b)/, '')
    indent ||= indent0
  end

  if trailing0 or eofnewline0 or expandtab0 or indent0
    File.binwrite(f, src)
    true
  end
end
if edited_files.empty?
  puts "All edited lines are formatted well:\n#{files.join("\n")}"
else
  msg = [('remove trailing spaces' if trailing),
         ('append newline at EOF' if eofnewline),
         ('expand tabs' if expandtab),
         ('adjust indents' if indent),
        ].compact
  message = "* #{msg.join(', ')}. [ci skip]"
  if expandtab
    message += "\nPlease consider using misc/expand_tabs.rb as a pre-commit hook."
  end
  if dry_run
    git.diff
    abort message
  else
    git.commit(message, *edited_files)
    git.push
  end
end
