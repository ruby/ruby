# vcs
require 'fileutils'
require 'optparse'

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
          opts.delete(:external_encoding)
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
          opts.delete(:external_encoding)
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

  def self.detect(path = '.', options = {}, argv = ::ARGV)
    uplevel_limit = options.fetch(:uplevel_limit, 0)
    curr = path
    begin
      @@dirs.each do |dir, klass, pred|
        if pred ? pred[curr, dir] : File.directory?(File.join(curr, dir))
          vcs = klass.new(curr)
          vcs.parse_options(argv)
          return vcs
        end
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

  def parse_options(opts, parser = OptionParser.new)
    case opts
    when Array
      parser.on("--[no-]dryrun") {|v| @dryrun = v}
      parser.on("--[no-]debug") {|v| @debug = v}
      parser.parse(opts)
      @debug = $DEBUG unless defined?(@debug)
      @dryrun = @debug unless defined?(@dryrun)
    when Hash
      unless (keys = opts.keys - [:debug, :dryrun]).empty?
        raise "Unknown options: #{keys.join(', ')}"
      end
      @debug = opts.fetch(:debug) {$DEBUG}
      @dryrun = opts.fetch(:dryrun) {@debug}
    end
  end

  attr_reader :dryrun, :debug
  alias dryrun? dryrun
  alias debug? debug

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
        _get_revisions(path, @srcdir)
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

  def revision_name(rev)
    self.class.revision_name(rev)
  end

  def short_revision(rev)
    self.class.short_revision(rev)
  end

  class SVN < self
    register(".svn")
    COMMAND = ENV['SVN'] || 'svn'

    def self.revision_name(rev)
      "r#{rev}"
    end

    def self.short_revision(rev)
      rev
    end

    def _get_revisions(path, srcdir = nil)
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
      return trunk if name == "trunk"
      url + "branches/#{name}"
    end

    def tag(name)
      url + "tags/#{name}"
    end

    def trunk
      url + "trunk"
    end
    alias master trunk

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

    def branch_beginning(url)
      # `--limit` of svn-log is useless in this case, because it is
      # applied before `--search`.
      rev = IO.pread(%W[ #{COMMAND} log --xml
                         --search=matz --search-and=has\ started
                         -- #{url}/version.h])[/<logentry\s+revision="(\d+)"/m, 1]
      rev.to_i if rev
    end

    def export_changelog(url, from, to, path)
      range = [to || 'HEAD', (from ? from+1 : branch_beginning(url))].compact.join(':')
      IO.popen({'TZ' => 'JST-9', 'LANG' => 'C', 'LC_ALL' => 'C'},
               %W"#{COMMAND} log -r#{range} #{url}") do |r|
        open(path, 'w') do |w|
          IO.copy_stream(r, w)
        end
      end
    end

    def commit
      args = %W"#{COMMAND} commit"
      if dryrun?
        STDERR.puts(args.inspect)
        return true
      end
      system(*args)
    end
  end

  class GIT < self
    register(".git") {|path, dir| File.exist?(File.join(path, dir))}
    COMMAND = ENV["GIT"] || 'git'

    def cmd_args(cmds, srcdir = nil)
      (opts = cmds.last).kind_of?(Hash) or cmds << (opts = {})
      opts[:external_encoding] ||= "UTF-8"
      if srcdir and self.class.local_path?(srcdir)
        opts[:chdir] ||= srcdir
      end
      STDERR.puts cmds.inspect if debug?
      cmds
    end

    def cmd_pipe_at(srcdir, cmds, &block)
      without_gitconfig { IO.popen(*cmd_args(cmds, srcdir), &block) }
    end

    def cmd_read_at(srcdir, cmds)
      without_gitconfig { IO.pread(*cmd_args(cmds, srcdir)) }
    end

    def cmd_pipe(*cmds, &block)
      cmd_pipe_at(@srcdir, cmds, &block)
    end

    def cmd_read(*cmds)
      cmd_read_at(@srcdir, cmds)
    end

    def _get_revisions(path, srcdir = nil)
      gitcmd = [COMMAND]
      last = cmd_read_at(srcdir, [[*gitcmd, 'rev-parse', 'HEAD']]).rstrip
      log = cmd_read_at(srcdir, [[*gitcmd, 'log', '-n1', '--date=iso', '--pretty=fuller', *path]])
      changed = log[/\Acommit (\h+)/, 1]
      modified = log[/^CommitDate:\s+(.*)/, 1]
      branch = cmd_read_at(srcdir, [gitcmd + %W[symbolic-ref --short HEAD]])
      if branch.empty?
        branch_list = cmd_read_at(srcdir, [gitcmd + %W[branch --list --contains HEAD]]).lines.to_a
        branch, = branch_list.grep(/\A\*/)
        case branch
        when /\A\* *\(\S+ detached at (.*)\)\Z/
          branch = $1
          branch = nil if last.start_with?(branch)
        when /\A\* (\S+)\Z/
          branch = $1
        else
          branch = nil
        end
        unless branch
          branch_list.each {|b| b.strip!}
          branch_list.delete_if {|b| / / =~ b}
          branch = branch_list.min_by(&:length) || ""
        end
      end
      branch.chomp!
      branch = ":detached:" if branch.empty?
      upstream = cmd_read_at(srcdir, [gitcmd + %W[branch --list --format=%(upstream:short) #{branch}]])
      upstream.chomp!
      title = cmd_read_at(srcdir, [gitcmd + %W[log --format=%s -n1 #{upstream}..HEAD]])
      title = nil if title.empty?
      [last, changed, modified, branch, title]
    end

    def self.revision_name(rev)
      short_revision(rev)
    end

    def self.short_revision(rev)
      rev[0, 10]
    end

    def without_gitconfig
      home = ENV.delete('HOME')
      yield
    ensure
      ENV['HOME'] = home if home
    end

    def initialize(*)
      super
      if srcdir = @srcdir and self.class.local_path?(srcdir)
        @srcdir = File.realpath(srcdir)
      end
      self
    end

    Branch = Struct.new(:to_str)

    def branch(name)
      Branch.new(name)
    end

    alias tag branch

    def master
      branch("master")
    end
    alias trunk master

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

    def branch_beginning(url)
      cmd_read(%W[ #{COMMAND} log -n1 --format=format:%H
                   --author=matz --committer=matz --grep=has\ started
                   -- version.h include/ruby/version.h])
    end

    def export_changelog(url, from, to, path)
      from, to = [from, to].map do |rev|
        rev or next
        if Integer === rev
          rev = cmd_read({'LANG' => 'C', 'LC_ALL' => 'C'},
                         %W"#{COMMAND} log -n1 --format=format:%H" <<
                         "--grep=^ *git-svn-id: .*@#{rev} ")
        end
        rev unless rev.empty?
      end
      unless /./.match(from ||= branch_beginning(url))
        raise "cannot find the beginning revision of the branch"
      end
      range = [from, (to || 'HEAD')].join('^..')
      cmd_pipe({'TZ' => 'JST-9', 'LANG' => 'C', 'LC_ALL' => 'C'},
               %W"#{COMMAND} log --format=medium --notes=commits --date=iso-local --topo-order #{range}", "rb") do |r|
        format_changelog(r, path)
      end
    end

    def format_changelog(r, path)
      IO.copy_stream(r, path)
    end

    def upstream
      (branch = cmd_read(%W"#{COMMAND} symbolic-ref --short HEAD")).chomp!
      (upstream = cmd_read(%W"#{COMMAND} branch --list --format=%(upstream) #{branch}")).chomp!
      while ref = upstream[%r"\Arefs/heads/(.*)", 1]
        upstream = cmd_read(%W"#{COMMAND} branch --list --format=%(upstream) #{ref}")
      end
      unless %r"\Arefs/remotes/([^/]+)/(.*)" =~ upstream
        raise "Upstream not found"
      end
      [$1, $2]
    end

    def commit(opts = {})
      args = [COMMAND, "push"]
      args << "-n" if dryrun
      remote, branch = upstream
      args << remote
      branches = %W[refs/notes/commits:refs/notes/commits HEAD:#{branch}]
      if dryrun?
        branches.each do |b|
          STDERR.puts((args + [b]).inspect)
        end
        return true
      end
      branches.each do |b|
        system(*(args + [b])) or return false
      end
      true
    end
  end

  class GITSVN < GIT
    def self.revision_name(rev)
      SVN.revision_name(rev)
    end

    def self.short_revision(rev)
      SVN.short_revision(rev)
    end

    def format_changelog(r, path)
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

    def last_changed_revision
      rev = cmd_read(%W"#{COMMAND} svn info"+[STDERR=>[:child, :out]])[/^Last Changed Rev: (\d+)/, 1]
      com = cmd_read(%W"#{COMMAND} svn find-rev r#{rev}").chomp
      return rev, com
    end

    def commit(opts = {})
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
