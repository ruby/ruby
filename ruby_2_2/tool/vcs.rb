# vcs

ENV.delete('PWD')

unless File.respond_to? :realpath
  require 'pathname'
  def File.realpath(arg)
    Pathname(arg).realpath.to_s
  end
end

def IO.pread(*args)
  STDERR.puts(*args.inspect) if $DEBUG
  popen(*args) {|f|f.read}
end

if RUBY_VERSION < "1.9"
  class IO
    @orig_popen = method(:popen)

    if defined?(fork)
      def self.popen(command, *rest, &block)
        if !(Array === command)
          @orig_popen.call(command, *rest, &block)
        elsif block
          @orig_popen.call("-", *rest) {|f| f ? yield(f) : exec(*command)}
        else
          @orig_popen.call("-", *rest) or exec(*command)
        end
      end
    else
      require 'shellwords'
      def self.popen(command, *rest, &block)
        command = command.shelljoin if Array === command
        @orig_popen.call(command, *rest, &block)
      end
    end
  end
end

class VCS
  class NotFoundError < RuntimeError; end

  @@dirs = []
  def self.register(dir)
    @@dirs << [dir, self]
  end

  def self.detect(path)
    @@dirs.each do |dir, klass|
      return klass.new(path) if File.directory?(File.join(path, dir))
      prev = path
      loop {
        curr = File.realpath(File.join(prev, '..'))
        break if curr == prev	# stop at the root directory
        return klass.new(path) if File.directory?(File.join(curr, dir))
        prev = curr
      }
    end
    raise VCS::NotFoundError, "does not seem to be under a vcs: #{path}"
  end

  def initialize(path)
    @srcdir = path
    super()
  end

  NullDevice = defined?(IO::NULL) ? IO::NULL :
    %w[/dev/null NUL NIL: NL:].find {|dev| File.exist?(dev)}

  # return a pair of strings, the last revision and the last revision in which
  # +path+ was modified.
  def get_revisions(path)
    if String === path or path.respond_to?(:to_path)
      path = relative_to(path)
    end
    last, changed, modified, *rest = (
      begin
        if NullDevice
          save_stderr = STDERR.dup
          STDERR.reopen NullDevice, 'w'
        end
        self.class.get_revisions(path, @srcdir)
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

  class SVN < self
    register(".svn")

    def self.get_revisions(path, srcdir = nil)
      if srcdir and (String === path or path.respond_to?(:to_path))
        path = File.join(srcdir, path)
      end
      info_xml = IO.pread(%W"svn info --xml #{path}")
      _, last, _, changed, _ = info_xml.split(/revision="(\d+)"/)
      modified = info_xml[/<date>([^<>]*)/, 1]
      [last, changed, modified]
    end

    def url
      unless defined?(@url)
        url = IO.pread(%W"svn info --xml #{@srcdir}")[/<root>(.*)<\/root>/, 1]
        @url = URI.parse(url+"/") if url
      end
      @url
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
      IO.popen(%W"svn ls #{branch('')}") do |f|
        f.each do |line|
          line.chomp!
          line.chomp!('/')
          yield(line) if File.fnmatch?(pat, line)
        end
      end
    end

    def grep(pat, tag, *files, &block)
      cmd = %W"svn cat"
      files.map! {|n| File.join(tag, n)} if tag
      set = block.binding.eval("proc {|match| $~ = match}")
      IO.popen([cmd, *files]) do |f|
        f.grep(pat) do |s|
          set[$~]
          yield s
        end
      end
    end

    def export(revision, url, dir)
      IO.popen(%W"svn export -r #{revision} #{url} #{dir}") do |pipe|
        pipe.each {|line| /^A/ =~ line or yield line}
      end
      $?.success?
    end
  end

  class GIT < self
    register(".git")

    def self.get_revisions(path, srcdir = nil)
      logcmd = %W[git log -n1 --date=iso]
      logcmd[1, 0] = ["-C", srcdir] if srcdir
      logcmd << "--grep=^ *git-svn-id: .*@[0-9][0-9]*"
      idpat = /git-svn-id: .*?@(\d+) \S+\Z/
      log = IO.pread(logcmd)
      last = log[idpat, 1]
      if path
        log = IO.pread(logcmd + [path])
        changed = log[idpat, 1]
      else
        changed = last
      end
      modified = log[/^Date:\s+(.*)/, 1]
      [last, changed, modified]
    end

    def branch(name)
      name
    end

    alias tag branch

    def trunk
      branch("trunk")
    end

    def stable
      cmd = %W"git for-each-ref --format=\%(refname:short) refs/heads/ruby_[0-9]*"
      cmd[1, 0] = ["-C", @srcdir] if @srcdir
      branch(IO.pread(cmd)[/.*^(ruby_\d+_\d+)$/m, 1])
    end

    def branch_list(pat)
      cmd = %W"git for-each-ref --format=\%(refname:short) refs/heads/#{pat}"
      cmd[1, 0] = ["-C", @srcdir] if @srcdir
      IO.popen(cmd) {|f|
        f.each {|line|
          line.chomp!
          yield line
        }
      }
    end

    def grep(pat, tag, *files, &block)
      cmd = %W[git grep -h --perl-regexp #{tag} --]
      cmd[1, 0] = ["-C", @srcdir] if @srcdir
      set = block.binding.eval("proc {|match| $~ = match}")
      IO.popen([cmd, *files]) do |f|
        f.grep(pat) do |s|
          set[$~]
          yield s
        end
      end
    end

    def export(revision, url, dir)
      ret = system("git", "clone", "-s", (@srcdir || '.'), "-b", url, dir)
      FileUtils.rm_rf("#{dir}/.git") if ret
      ret
    end
  end
end
