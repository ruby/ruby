# vcs
require 'fileutils'
require 'optparse'

# This library is used by several other tools/ scripts to detect the current
# VCS in use (e.g. SVN, Git) or to interact with that VCS.

ENV.delete('PWD')

class VCS
  DEBUG_OUT = STDERR.dup
end

unless File.respond_to? :realpath
  require 'pathname'
  def File.realpath(arg)
    Pathname(arg).realpath.to_s
  end
end

def IO.pread(*args)
  VCS::DEBUG_OUT.puts(args.inspect) if $DEBUG
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
        VCS::DEBUG_OUT.puts args.inspect if $DEBUG
        super
      end
    end
  ensure
    $VERBOSE = verbose unless verbose.nil?
  end
  using DebugPOpen
  module DebugSystem
    def system(*args)
      VCS::DEBUG_OUT.puts args.inspect if $DEBUG
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

  def self.detect(path = '.', options = {}, parser = nil)
    uplevel_limit = options.fetch(:uplevel_limit, 0)
    curr = path
    begin
      @@dirs.each do |dir, klass, pred|
        if pred ? pred[curr, dir] : File.directory?(File.join(curr, dir))
          vcs = klass.new(curr)
          vcs.define_options(parser) if parser
          vcs.set_options(options)
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

  def self.define_options(parser, opts = {})
    parser.separator("  VCS common options:")
    parser.define("--[no-]dryrun") {|v| opts[:dryrun] = v}
    parser.define("--[no-]debug") {|v| opts[:debug] = v}
    opts
  end

  attr_reader :srcdir

  def initialize(path)
    @srcdir = path
    super()
  end

  def chdir(path)
    @srcdir = path
  end

  def define_options(parser)
  end

  def set_options(opts)
    @debug = opts.fetch(:debug) {$DEBUG}
    @dryrun = opts.fetch(:dryrun) {@debug}
  end

  attr_reader :dryrun, :debug
  alias dryrun? dryrun
  alias debug? debug

  NullDevice = defined?(IO::NULL) ? IO::NULL :
    %w[/dev/null NUL NIL: NL:].find {|dev| File.exist?(dev)}

  # returns
  # * the last revision of the current branch
  # * the last revision in which +path+ was modified
  # * the last modified time of +path+
  # * the last commit title since the latest upstream
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
    FileUtils.rm_rf(Dir.glob("#{dir}/.git*"))
  end

  def revision_handler(rev)
    self.class
  end

  def revision_name(rev)
    revision_handler(rev).revision_name(rev)
  end

  def short_revision(rev)
    revision_handler(rev).short_revision(rev)
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
      if srcdir and self.class.local_path?(path)
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
      [Integer(last), Integer(changed), modified, branch]
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
      @url ||= begin
        url = get_info[/<root>(.*)<\/root>/, 1]
        @url = URI.parse(url+"/") if url
      end
    end

    def wcroot
      @wcroot ||= begin
        info = get_info
        @wcroot = info[/<wcroot-abspath>(.*)<\/wcroot-abspath>/, 1]
        @wcroot ||= self.class.search_root(@srcdir)
      end
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
          return self
        end
      end
      IO.popen(%W"#{COMMAND} export -r #{revision} #{url} #{dir}") do |pipe|
        pipe.each {|line| /^A/ =~ line or yield line}
      end
      self if $?.success?
    end

    def after_export(dir)
      super
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
        VCS::DEBUG_OUT.puts(args.inspect)
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
      if srcdir
        opts[:chdir] ||= srcdir
      end
      VCS::DEBUG_OUT.puts cmds.inspect if debug?
      cmds
    end

    def cmd_pipe_at(srcdir, cmds, &block)
      without_gitconfig { IO.popen(*cmd_args(cmds, srcdir), &block) }
    end

    def cmd_read_at(srcdir, cmds)
      result = without_gitconfig { IO.pread(*cmd_args(cmds, srcdir)) }
      VCS::DEBUG_OUT.puts result.inspect if debug?
      result
    end

    def cmd_pipe(*cmds, &block)
      cmd_pipe_at(@srcdir, cmds, &block)
    end

    def cmd_read(*cmds)
      cmd_read_at(@srcdir, cmds)
    end

    def svn_revision(log)
      if /^ *git-svn-id: .*@(\d+) .*\n+\z/ =~ log
        $1.to_i
      end
    end

    def _get_revisions(path, srcdir = nil)
      ref = Branch === path ? path.to_str : 'HEAD'
      gitcmd = [COMMAND]
      last = cmd_read_at(srcdir, [[*gitcmd, 'rev-parse', ref]]).rstrip
      log = cmd_read_at(srcdir, [[*gitcmd, 'log', '-n1', '--date=iso', '--pretty=fuller', *path]])
      changed = log[/\Acommit (\h+)/, 1]
      modified = log[/^CommitDate:\s+(.*)/, 1]
      if rev = svn_revision(log)
        if changed == last
          last = rev
        else
          svn_rev = svn_revision(cmd_read_at(srcdir, [[*gitcmd, 'log', '-n1', '--format=%B', last]]))
          last = svn_rev if svn_rev
        end
        changed = rev
      end
      branch = cmd_read_at(srcdir, [gitcmd + %W[symbolic-ref --short #{ref}]])
      if branch.empty?
        branch = cmd_read_at(srcdir, [gitcmd + %W[describe --contains #{ref}]]).strip
      end
      if branch.empty?
        branch_list = cmd_read_at(srcdir, [gitcmd + %W[branch --list --contains #{ref}]]).lines.to_a
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
      title = cmd_read_at(srcdir, [gitcmd + %W[log --format=%s -n1 #{upstream}..#{ref}]])
      title = nil if title.empty?
      [last, changed, modified, branch, title]
    end

    def self.revision_name(rev)
      short_revision(rev)
    end

    def self.short_revision(rev)
      rev[0, 10]
    end

    def revision_handler(rev)
      case rev
      when Integer
        SVN
      else
        super
      end
    end

    def without_gitconfig
      home = ENV.delete('HOME')
      yield
    ensure
      ENV['HOME'] = home if home
    end

    def initialize(*)
      super
      @srcdir = File.realpath(@srcdir)
      VCS::DEBUG_OUT.puts @srcdir.inspect if debug?
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
      system(COMMAND, "clone", "-c", "advice.detachedHead=false", "-s", (@srcdir || '.').to_s, "-b", url, dir) or return
      (Integer === revision ? GITSVN : GIT).new(File.expand_path(dir))
    end

    def branch_beginning(url)
      cmd_read(%W[ #{COMMAND} log -n1 --format=format:%H
                   --author=matz --committer=matz --grep=has\ started
                   #{url.to_str} -- version.h include/ruby/version.h])
    end

    def export_changelog(url, from, to, path)
      svn = nil
      from, to = [from, to].map do |rev|
        rev or next
        if Integer === rev
          svn = true
          rev = cmd_read({'LANG' => 'C', 'LC_ALL' => 'C'},
                         %W"#{COMMAND} log -n1 --format=format:%H" <<
                         "--grep=^ *git-svn-id: .*@#{rev} ")
        end
        rev unless rev.empty?
      end
      unless (from && /./.match(from)) or ((from = branch_beginning(url)) && /./.match(from))
        warn "no starting commit found", uplevel: 1
        from = nil
      end
      unless svn or system(*%W"#{COMMAND} fetch origin refs/notes/commits:refs/notes/commits",
                           chdir: @srcdir, exception: false)
        abort "Could not fetch notes/commits tree"
      end
      system(*%W"#{COMMAND} fetch origin refs/notes/log-fix:refs/notes/log-fix",
               chdir: @srcdir, exception: false)
      to ||= url.to_str
      if from
        arg = ["#{from}^..#{to}"]
      else
        arg = ["--since=25 Dec 00:00:00", to]
      end
      if svn
        format_changelog_as_svn(path, arg)
      else
        format_changelog(path, arg)
      end
    end

    def format_changelog(path, arg)
      env = {'TZ' => 'JST-9', 'LANG' => 'C', 'LC_ALL' => 'C'}
      cmd = %W"#{COMMAND} log --format=medium --notes=commits --notes=log-fix --topo-order --no-merges"
      date = "--date=iso-local"
      unless system(env, *cmd, date, chdir: @srcdir, out: NullDevice, exception: false)
        date = "--date=iso"
      end
      cmd << date
      cmd.concat(arg)
      File.open(path, 'w') do |w|
        cmd_pipe(env, cmd, chdir: @srcdir) do |r|
          while s = r.gets("\ncommit ")
            if s.sub!(/\nNotes \(log-fix\):\n((?: +.*\n)+)/, '')
              fix = $1
              h, s = s.split(/^$/, 2)
              s = s.lines
              fix.each_line do |x|
                if %r[^ +(\d+)s/(.+)/(.+)/] =~ x
                  s[$1.to_i][$2] = $3
                end
              end
              s = [h, s.join('')].join('')
            end
            s.gsub!(/ +\n/, "\n")
            w.print s
          end
        end
      end
    end

    def format_changelog_as_svn(path, arg)
      cmd = %W"#{COMMAND} log --topo-order --no-notes -z --format=%an%n%at%n%B"
      cmd.concat(arg)
      open(path, 'w') do |w|
        sep = "-"*72 + "\n"
        w.print sep
        cmd_pipe(cmd) do |r|
          while s = r.gets("\0")
            s.chomp!("\0")
            author, time, s = s.split("\n", 3)
            s.sub!(/\n\ngit-svn-id: .*@(\d+) .*\n\Z/, '')
            rev = $1
            time = Time.at(time.to_i).getlocal("+09:00").strftime("%F %T %z (%a, %d %b %Y)")
            lines = s.count("\n") + 1
            lines = "#{lines} line#{lines == 1 ? '' : 's'}"
            w.print "r#{rev} | #{author} | #{time} | #{lines}\n\n", s, "\n", sep
          end
        end
      end
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
          VCS::DEBUG_OUT.puts((args + [b]).inspect)
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
