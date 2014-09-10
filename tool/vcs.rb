# vcs

ENV.delete('PWD')

unless File.respond_to? :realpath
  require 'pathname'
  def File.realpath(arg)
    Pathname(arg).realpath.to_s
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

  # return a pair of strings, the last revision and the last revision in which
  # +path+ was modified.
  def get_revisions(path)
    path = relative_to(path)
    last, changed, modified, *rest = Dir.chdir(@srcdir) {self.class.get_revisions(path)}
    last or raise VCS::NotFoundError, "last revision not found"
    changed or raise VCS::NotFoundError, "changed revision not found"
    if modified
      /\A(\d+)-(\d+)-(\d+)\D(\d+):(\d+):(\d+(?:\.\d+)?)\s*(?:Z|([-+]\d\d)(\d\d))\z/ =~ modified or
        raise "unknown time format - #{modified}"
      modified = Time.mktime(*($~[1..6] + [$7 ? "#{$7}:#{$8}" : "+00:00"]))
    end
    return last, changed, modified, *rest
  end

  def relative_to(path)
    if path
      srcdir = File.realpath(@srcdir)
      path = File.realpath(path)
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

    def self.get_revisions(path)
      begin
        nulldevice = %w[/dev/null NUL NIL: NL:].find {|dev| File.exist?(dev)}
        if nulldevice
          save_stderr = STDERR.dup
          STDERR.reopen nulldevice, 'w'
        end
        info_xml = `svn info --xml "#{path}"`
      ensure
        if save_stderr
          STDERR.reopen save_stderr
          save_stderr.close
        end
      end
      _, last, _, changed, _ = info_xml.split(/revision="(\d+)"/)
      modified = info_xml[/<date>([^<>]*)/, 1]
      [last, changed, modified]
    end
  end

  class GIT < self
    register(".git")

    def self.get_revisions(path)
      logcmd = %Q[git log -n1 --date=iso --grep="^ *git-svn-id: .*@[0-9][0-9]* "]
      idpat = /git-svn-id: .*?@(\d+) \S+\Z/
      last = `#{logcmd}`[idpat, 1]
      if path
        log = `#{logcmd} "#{path}"`
        changed = log[idpat, 1]
      else
        changed = last
      end
      modified = log[/^Date:\s+(.*)/, 1]
      [last, changed, modified]
    end
  end
end
