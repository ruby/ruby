#!/usr/bin/env ruby --disable-gems
# Add the following line to your `.git/hooks/pre-commit`:
#
#   $ ruby --disable-gems misc/expand_tabs.rb
#

require 'shellwords'
require 'tmpdir'
ENV['LC_ALL'] = 'C'

class Git
  def initialize(oldrev, newrev)
    @oldrev = oldrev
    @newrev = newrev
  end

  # ["foo/bar.c", "baz.h", ...]
  def updated_paths
    with_clean_env do
      IO.popen(['git', 'diff', '--cached', '--name-only', @newrev], &:readlines).each(&:chomp!)
    end
  end

  # [0, 1, 4, ...]
  def updated_lines(file)
    lines = []
    revs_pattern = ("0"*40) + " "
    with_clean_env { IO.popen(['git', 'blame', '-l', '--', file], &:readlines) }.each_with_index do |line, index|
      if line.b.start_with?(revs_pattern)
        lines << index
      end
    end
    lines
  end

  def add(file)
    git('add', file)
  end

  def toplevel
    IO.popen(['git', 'rev-parse', '--show-toplevel'], &:read).chomp
  end

  private

  def git(*args)
    cmd = ['git', *args].shelljoin
    unless with_clean_env { system(cmd) }
      abort "Failed to run: #{cmd}"
    end
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
  racc
  rdoc
  rexml
  rss
  scanf
  shell
  sync
  thwait
  tracer
]

DEFAULT_GEM_EXTS = %w[
  bigdecimal
  date
  dbm
  etc
  fcntl
  fiddle
  gdbm
  io/console
  json
  openssl
  psych
  stringio
  strscan
  zlib
]

EXPANDTAB_IGNORED_FILES = [
  # default gems whose master is GitHub
  %r{\Abin/(?!erb)\w+\z},
  *DEFAULT_GEM_LIBS.flat_map { |lib|
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

  # vendoring (onigmo)
  %r{\Aenc/},
  %r{\Ainclude/ruby/onigmo\.h\z},
  %r{\Areg.+\.(c|h)\z},

  # explicit or implicit `c-file-style: "linux"`
  %r{\Aaddr2line\.c\z},
  %r{\Amissing/},
  %r{\Astrftime\.c\z},
  %r{\Avsnprintf\.c\z},
]

git = Git.new('HEAD^', 'HEAD')

Dir.chdir(git.toplevel) do
  paths = git.updated_paths
  paths.select! {|f|
    (f.end_with?('.c') || f.end_with?('.h') || f == 'insns.def') && EXPANDTAB_IGNORED_FILES.all? { |re| !f.match(re) }
  }
  files = paths.select {|n| File.file?(n)}
  exit if files.empty?

  files.each do |f|
    src = File.binread(f) rescue next

    expanded = false
    updated_lines = git.updated_lines(f)
    unless updated_lines.empty?
      src.gsub!(/^.*$/).with_index do |line, lineno|
        if updated_lines.include?(lineno) && line.start_with?("\t") # last-committed line with hard tabs
          expanded = true
          line.sub(/\A\t+/) { |tabs| ' ' * (8 * tabs.length) }
        else
          line
        end
      end
    end

    if expanded
      File.binwrite(f, src)
      git.add(f)
    end
  end
end
