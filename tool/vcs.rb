# vcs
require 'fileutils'

# This library is used by several other tools/ scripts to detect the current
# VCS in use (e.g. SVN, Git) or to interact with that VCS.

ENV.delete('PWD')

unless File.respond_to? :realpath
  require 'pathname'
  def File.realpath(arg)
    Pathname(arg).realpath.to_s
  end
end

def IO.pread(*args)
  STDERR.puts(args.inspect) if $DEBUG
  popen(*args) {|f|f.read}
end

if RUBY_VERSION < "2.0"
  class IO
    @orig_popen = method(:popen)

    if defined?(fork)
      def self.popen(command, *rest, &block)
        if command.kind_of?(Hash)
          env = command
          command = rest.shift
        end
        opts = rest.last
        if opts.kind_of?(Hash)
          dir = opts.delete(:chdir)
          rest.pop if opts.empty?
        end

        if block
          @orig_popen.call("-", *rest) do |f|
            if f
              yield(f)
            else
              Dir.chdir(dir) if dir
              ENV.replace(env) if env
              exec(*command)
            end
          end
        else
          f = @orig_popen.call("-", *rest)
          unless f
            Dir.chdir(dir) if dir
            ENV.replace(env) if env
            exec(*command)
          end
          f
        end
      end
    else
      require 'shellwords'
      def self.popen(command, *rest, &block)
        if command.kind_of?(Hash)
          env = command
          oldenv = ENV.to_hash
          command = rest.shift
        end
        opts = rest.last
        if opts.kind_of?(Hash)
          dir = opts.delete(:chdir)
          rest.pop if opts.empty?
        end

        command = command.shelljoin if Array === command
        Dir.chdir(dir || ".") do
          ENV.replace(env) if env
          @orig_popen.call(command, *rest, &block)
          ENV.replace(oldenv) if oldenv
        end
      end
    end
  end
else
  module DebugPOpen
    verbose, $VERBOSE = $VERBOSE, nil if RUBY_VERSION < "2.1"
    refine IO.singleton_class do
      def popen(*args)
        STDERR.puts args.inspect if $DEBUG
        super
      end
    end
  ensure
    $VERBOSE = verbose unless verbose.nil?
  end
  using DebugPOpen
  module DebugSystem
    def system(*args)
      STDERR.puts args.inspect if $DEBUG
      exception = false
      opts = Hash.try_convert(args[-1])
      if RUBY_VERSION >= "2.6"
        unless opts
          opts = {}
          args << opts
        end
        exception = opts.fetch(:exception) {opts[:exception] = true}
      elsif opts
        exception = opts.delete(:exception) {true}
        args.pop if opts.empty?
      end
      ret = super(*args)
      raise "Command failed with status (#$?): #{args[0]}" if exception and !ret
      ret
    end
  end
  module Kernel
    prepend(DebugSystem)
  end
end

class VCS
  prepend(DebugSystem) if defined?(DebugSystem)
  class NotFoundError < RuntimeError; end

  @@dirs = []
  def self.register(dir, &pred)
    @@dirs << [dir, self, pred]
  end

  def self.detect(path, uplevel_limit: 0)
    curr = path
    begin
      @@dirs.each do |dir, klass, pred|
        return klass.new(curr) if pred ? pred[curr, dir] : File.directory?(File.join(curr, dir))
      end
      if uplevel_limit
        break if uplevel_limit.zero?
        uplevel_limit -= 1
      end
      prev, curr = curr, File.realpath(File.join(curr, '..'))
    end until curr == prev # stop at the root directory
    raise VCS::NotFoundError, "does not seem to be under a vcs: #{path}"
  end

  def self.local_path?(path)
    String === path or path.respond_to?(:to_path)
  end

  attr_reader :srcdir

  def initialize(path)
    @srcdir = path
    super()
  end

  NullDevice = defined?(IO::NULL) ? IO::NULL :
    %w[/dev/null NUL NIL: NL:].find {|dev| File.exist?(dev)}

  # return a pair of strings, the last revision and the last revision in which
  # +path+ was modified.
  def get_revisions(path)
    if self.class.local_path?(path)
      path = relative_to(path)
    end
    last, changed, modified, *rest = (
      begin
        if NullDevice
          save_stderr = STDERR.dup
          STDERR.reopen NullDevice, 'w'
        end
        self.class.get_revisions(path, @srcdir)
      rescue Errno::ENOENT => e
        raise VCS::NotFoundError, e.message
      ensure
        if save_stderr
          STDERR.reopen save_stderr
          save_stderr.close
        end
      end
    )
    last or raise VCS::NotFoundError, "last revision not found"
    changed or raise VCS::NotFoundError, "changed revision not found"
    if modified
      /\A(\d+)-(\d+)-(\d+)\D(\d+):(\d+):(\d+(?:\.\d+)?)\s*(?:Z|([-+]\d\d)(\d\d))\z/ =~ modified or
        raise "unknown time format - #{modified}"
      match = $~[1..6].map { |x| x.to_i }
      off = $7 ? "#{$7}:#{$8}" : "+00:00"
      match << off
      begin
        modified = Time.new(*match)
      rescue ArgumentError
        modified = Time.utc(*$~[1..6]) + $7.to_i * 3600 + $8.to_i * 60
      end
    end
    return last, changed, modified, *rest
  end

  def modified(path)
    _, _, modified, * = get_revisions(path)
    modified
  end

  def relative_to(path)
    if path
      srcdir = File.realpath(@srcdir)
      path = File.realdirpath(path)
      list1 = srcdir.split(%r{/})
      list2 = path.split(%r{/})
      while !list1.empty? && !list2.empty? && list1.first == list2.first
        list1.shift
        list2.shift
      end
      if list1.empty? && list2.empty?
        "."
      else
        ([".."] * list1.length + list2).join("/")
      end
    else
      '.'
    end
  end

  def after_export(dir)
  end

  class SVN < self
    register(".svn")
    COMMAND = ENV['SVN'] || 'svn'

    def self.get_revisions(path, srcdir = nil)
      if srcdir and local_path?(path)
        path = File.join(srcdir, path)
      end
      if srcdir
        info_xml = IO.pread(%W"#{COMMAND} info --xml #{srcdir}")
        info_xml = nil unless info_xml[/<url>(.*)<\/url>/, 1] == path.to_s
      end
      info_xml ||= IO.pread(%W"#{COMMAND} info --xml #{path}")
      _, last, _, changed, _ = info_xml.split(/revision="(\d+)"/)
      modified = info_xml[/<date>([^<>]*)/, 1]
      branch = info_xml[%r'<relative-url>\^/(?:branches/|tags/)?([^<>]+)', 1]
      [last, changed, modified, branch]
    end

    def self.search_root(path)
      return unless local_path?(path)
      parent = File.realpath(path)
      begin
        parent = File.dirname(wkdir = parent)
        return wkdir if File.directory?(wkdir + "/.svn")
      end until parent == wkdir
    end

    def get_info
      @info ||= IO.pread(%W"#{COMMAND} info --xml #{@srcdir}")
    end

    def url
      unless @url
        url = get_info[/<root>(.*)<\/root>/, 1]
        @url = URI.parse(url+"/") if url
      end
      @url
    end

    def wcroot
      unless @wcroot
        info = get_info
        @wcroot = info[/<wcroot-abspath>(.*)<\/wcroot-abspath>/, 1]
        @wcroot ||= self.class.search_root(@srcdir)
      end
      @wcroot
    end

    def branch(name)
      url + "branches/#{name}"
    end

    def tag(name)
      url + "tags/#{name}"
    end

    def trunk
      url + "trunk"
    end

    def branch_list(pat)
      IO.popen(%W"#{COMMAND} ls #{branch('')}") do |f|
        f.each do |line|
          line.chomp!
          line.chomp!('/')
          yield(line) if File.fnmatch?(pat, line)
        end
      end
    end

    def grep(pat, tag, *files, &block)
      cmd = %W"#{COMMAND} cat"
      files.map! {|n| File.join(tag, n)} if tag
      set = block.binding.eval("proc {|match| $~ = match}")
      IO.popen([cmd, *files]) do |f|
        f.grep(pat) do |s|
          set[$~]
          yield s
        end
      end
    end

    def export(revision, url, dir, keep_temp = false)
      if @srcdir and (rootdir = wcroot)
        srcdir = File.realpath(@srcdir)
        rootdir << "/"
        if srcdir.start_with?(rootdir)
          subdir = srcdir[rootdir.size..-1]
          subdir = nil if subdir.empty?
          FileUtils.mkdir_p(svndir = dir+"/.svn")
          FileUtils.ln_s(Dir.glob(rootdir+"/.svn/*"), svndir)
          system(COMMAND, "-q", "revert", "-R", subdir || ".", :chdir => dir) or return false
          FileUtils.rm_rf(svndir) unless keep_temp
          if subdir
            tmpdir = Dir.mktmpdir("tmp-co.", "#{dir}/#{subdir}")
            File.rename(tmpdir, tmpdir = "#{dir}/#{File.basename(tmpdir)}")
            FileUtils.mv(Dir.glob("#{dir}/#{subdir}/{.[^.]*,..?*,*}"), tmpdir)
            begin
              Dir.rmdir("#{dir}/#{subdir}")
            end until (subdir = File.dirname(subdir)) == '.'
            FileUtils.mv(Dir.glob("#{tmpdir}/#{subdir}/{.[^.]*,..?*,*}"), dir)
            Dir.rmdir(tmpdir)
          end
          return true
        end
      end
      IO.popen(%W"#{COMMAND} export -r #{revision} #{url} #{dir}") do |pipe|
        pipe.each {|line| /^A/ =~ line or yield line}
      end
      $?.success?
    end

    def after_export(dir)
      FileUtils.rm_rf(dir+"/.svn")
    end

    def export_changelog(url, from, to, path)
      range = [to, (from+1 if from)].compact.join(':')
      IO.popen({'TZ' => 'JST-9', 'LANG' => 'C', 'LC_ALL' => 'C'},
               %W"#{COMMAND} log -r#{range} #{url}") do |r|
        open(path, 'w') do |w|
          IO.copy_stream(r, w)
        end
      end
    end

    def commit
      system(*%W"#{COMMAND} commit")
    end
  end

  class GIT < self
    register(".git") {|path, dir| File.exist?(File.join(path, dir))}
    COMMAND = ENV["GIT"] || 'git'

    def self.cmd_args(cmds, srcdir = nil)
      if srcdir and local_path?(srcdir)
        (opts = cmds.last).kind_of?(Hash) or cmds << (opts = {})
        opts[:chdir] ||= srcdir
      end
      cmds
    end

    def self.cmd_pipe_at(srcdir, cmds, &block)
      IO.popen(*cmd_args(cmds, srcdir), &block)
    end

    def self.cmd_read_at(srcdir, cmds)
      IO.pread(*cmd_args(cmds, srcdir))
    end

    def self.get_revisions(path, srcdir = nil)
      gitcmd = [COMMAND]
      desc = cmd_read_at(srcdir, [gitcmd + %w[describe --tags --match REV_*]])
      if /\AREV_(\d+)(?:-(\d+)-g\h+)?\Z/ =~ desc
        last = ($1.to_i + $2.to_i).to_s
      end
      logcmd = gitcmd + %W[log -n1 --date=iso]
      logcmd << "--grep=^ *git-svn-id: .*@[0-9][0-9]*" unless last
      idpat = /git-svn-id: .*?@(\d+) \S+\Z/
      log = cmd_read_at(srcdir, [logcmd])
      commit = log[/\Acommit (\w+)/, 1]
      last ||= log[idpat, 1]
      if path
        cmd = logcmd
        cmd += [path] unless path == '.'
        log = cmd_read_at(srcdir, [cmd])
        changed = log[idpat, 1] || last
      else
        changed = last
      end
      modified = log[/^Date:\s+(.*)/, 1]
      branch = cmd_read_at(srcdir, [gitcmd + %W[symbolic-ref HEAD]])[%r'\A(?:refs/heads/)?(.+)', 1]
      title = cmd_read_at(srcdir, [gitcmd + %W[log --format=%s -n1 #{commit}..HEAD]])
      title = nil if title.empty?
      [last, changed, modified, branch, title]
    end

    def initialize(*)
      super
      if srcdir = @srcdir and self.class.local_path?(srcdir)
        @srcdir = File.realpath(srcdir)
      end
      self
    end

    def cmd_pipe(*cmds, &block)
      self.class.cmd_pipe_at(@srcdir, cmds, &block)
    end

    def cmd_read(*cmds)
      self.class.cmd_read_at(@srcdir, cmds)
    end

    Branch = Struct.new(:to_str)

    def branch(name)
      Branch.new(name)
    end

    alias tag branch

    def trunk
      branch("trunk")
    end

    def stable
      cmd = %W"#{COMMAND} for-each-ref --format=\%(refname:short) refs/heads/ruby_[0-9]*"
      branch(cmd_read(cmd)[/.*^(ruby_\d+_\d+)$/m, 1])
    end

    def branch_list(pat)
      cmd = %W"#{COMMAND} for-each-ref --format=\%(refname:short) refs/heads/#{pat}"
      cmd_pipe(cmd) {|f|
        f.each {|line|
          line.chomp!
          yield line
        }
      }
    end

    def grep(pat, tag, *files, &block)
      cmd = %W[#{COMMAND} grep -h --perl-regexp #{tag} --]
      set = block.binding.eval("proc {|match| $~ = match}")
      cmd_pipe(cmd+files) do |f|
        f.grep(pat) do |s|
          set[$~]
          yield s
        end
      end
    end

    def export(revision, url, dir, keep_temp = false)
      ret = system(COMMAND, "clone", "-s", (@srcdir || '.').to_s, "-b", url, dir)
      ret
    end

    def after_export(dir)
      FileUtils.rm_rf(Dir.glob("#{dir}/.git*"))
    end

    def export_changelog(url, from, to, path)
      range = [from, to].map do |rev|
        rev or next
        rev = cmd_read({'LANG' => 'C', 'LC_ALL' => 'C'},
                       %W"#{COMMAND} log -n1 --format=format:%H" <<
                       "--grep=^ *git-svn-id: .*@#{rev} ")
        rev unless rev.empty?
      end.join('..')
      cmd_pipe({'TZ' => 'JST-9', 'LANG' => 'C', 'LC_ALL' => 'C'},
               %W"#{COMMAND} log --no-notes --date=iso-local --topo-order #{range}", "rb") do |r|
        open(path, 'w') do |w|
          sep = "-"*72
          w.puts sep
          while s = r.gets('')
            author = s[/^Author:\s*(\S+)/, 1]
            time = s[/^Date:\s*(.+)/, 1]
            s = r.gets('')
            s.gsub!(/^ {4}/, '')
            s.sub!(/^git-svn-id: .*@(\d+) .*\n+\z/, '')
            rev = $1
            s.gsub!(/^ {8}/, '') if /^(?! {8}|$)/ !~ s
            s.sub!(/\n\n\z/, "\n")
            if /\A(\d+)-(\d+)-(\d+)/ =~ time
              date = Time.new($1.to_i, $2.to_i, $3.to_i).strftime("%a, %d %b %Y")
            end
            lines = s.count("\n")
            lines = "#{lines} line#{lines == 1 ? '' : 's'}"
            w.puts "r#{rev} | #{author} | #{time} (#{date}) | #{lines}\n\n"
            w.puts s, sep
          end
        end
      end
    end

    def last_changed_revision
      rev = cmd_read(%W"#{COMMAND} svn info"+[STDERR=>[:child, :out]])[/^Last Changed Rev: (\d+)/, 1]
      com = cmd_read(%W"#{COMMAND} svn find-rev r#{rev}").chomp
      return rev, com
    end

    def commit(opts = {})
      dryrun = opts.fetch(:dryrun) {$DEBUG} if opts
      rev, com = last_changed_revision
      head = cmd_read(%W"#{COMMAND} symbolic-ref --short HEAD").chomp

      commits = cmd_read([COMMAND, "log", "--reverse", "--format=%H %ae %ce", "#{com}..@"], "rb").split("\n")
      commits.each_with_index do |l, i|
        r, a, c = l.split
        dcommit = [COMMAND, "svn", "dcommit"]
        dcommit.insert(-2, "-n") if dryrun
        dcommit << "--add-author-from" unless a == c
        dcommit << r
        system(*dcommit) or return false
        system(COMMAND, "checkout", head) or return false
        system(COMMAND, "rebase") or return false
      end

      if rev
        old = [cmd_read(%W"#{COMMAND} log -1 --format=%H").chomp]
        old << cmd_read(%W"#{COMMAND} svn reset -r#{rev}")[/^r#{rev} = (\h+)/, 1]
        3.times do
          sleep 2
          system(*%W"#{COMMAND} pull --no-edit --rebase")
          break unless old.include?(cmd_read(%W"#{COMMAND} log -1 --format=%H").chomp)
        end
      end
      true
    end
  end
end
