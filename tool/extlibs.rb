#!/usr/bin/ruby

# Used to download, extract and patch extension libraries (extlibs)
# for Ruby. See common.mk for Ruby's usage.

require 'digest'
require_relative 'downloader'
begin
  require_relative 'lib/colorize'
rescue LoadError
end

class ExtLibs
  unless defined?(Colorize)
    class Colorize
      def pass(str) str; end
      def fail(str) str; end
    end
  end

  class Vars < Hash
    def pattern
      /\$\((#{Regexp.union(keys)})\)/
    end

    def expand(str)
      if empty?
        str
      else
        str.gsub(pattern) {self[$1]}
      end
    end
  end

  def initialize(mode = :all, cache_dir: nil)
    @mode = mode
    @cache_dir = cache_dir
    @colorize = Colorize.new
  end

  def cache_file(url, cache_dir)
    Downloader.cache_file(url, nil, cache_dir).to_path
  end

  def do_download(url, cache_dir)
    Downloader.download(url, nil, nil, nil, :cache_dir => cache_dir)
  end

  def do_checksum(cache, chksums)
    chksums.each do |sum|
      name, sum = sum.split(/:/)
      if $VERBOSE
        $stdout.print "checking #{name} of #{cache} ..."
        $stdout.flush
      end
      hd = Digest(name.upcase).file(cache).hexdigest
      if $VERBOSE
        $stdout.print " "
        $stdout.puts hd == sum ? @colorize.pass("OK") : @colorize.fail("NG")
        $stdout.flush
      end
      unless hd == sum
        raise "checksum mismatch: #{cache}, #{name}:#{hd}, expected #{sum}"
      end
    end
  end

  def do_extract(cache, dir)
    if $VERBOSE
      $stdout.puts "extracting #{cache} into #{dir}"
      $stdout.flush
    end
    ext = File.extname(cache)
    case ext
    when '.gz', '.tgz'
      f = IO.popen(["gzip", "-dc", cache])
      cache = cache.chomp('.gz')
    when '.bz2', '.tbz'
      f = IO.popen(["bzip2", "-dc", cache])
      cache = cache.chomp('.bz2')
    when '.xz', '.txz'
      f = IO.popen(["xz", "-dc", cache])
      cache = cache.chomp('.xz')
    else
      inp = cache
    end
    inp ||= f.binmode
    ext = File.extname(cache)
    case ext
    when '.tar', /\A\.t[gbx]z\z/
      pid = Process.spawn("tar", "xpf", "-", in: inp, chdir: dir)
    when '.zip'
      pid = Process.spawn("unzip", inp, "-d", dir)
    end
    f.close if f
    Process.wait(pid)
    $?.success? or raise "failed to extract #{cache}"
  end

  def do_patch(dest, patch, args)
    if $VERBOSE
      $stdout.puts "applying #{patch} under #{dest}"
      $stdout.flush
    end
    Process.wait(Process.spawn(ENV.fetch("PATCH", "patch"), "-d", dest, "-i", patch, *args))
    $?.success? or raise "failed to patch #{patch}"
  end

  def do_link(file, src, dest)
    file = File.join(dest, file)
    if (target = src).start_with?("/")
      target = File.join([".."] * file.count("/"), src)
    end
    return unless File.exist?(File.expand_path(target, File.dirname(file)))
    File.unlink(file) rescue nil
    begin
      File.symlink(target, file)
    rescue
    else
      if $VERBOSE
        $stdout.puts "linked #{target} to #{file}"
        $stdout.flush
      end
      return
    end
    begin
      src = src.sub(/\A\//, '')
      File.copy_stream(src, file)
    rescue
      if $VERBOSE
        $stdout.puts "failed to link #{src} to #{file}: #{$!.message}"
      end
    else
      if $VERBOSE
        $stdout.puts "copied #{src} to #{file}"
      end
    end
  end

  def do_exec(command, dir, dest)
    dir = dir ? File.join(dest, dir) : dest
    if $VERBOSE
      $stdout.puts "running #{command.dump} under #{dir}"
      $stdout.flush
    end
    system(command, chdir: dir) or raise "failed #{command.dump}"
  end

  def do_command(mode, dest, url, cache_dir, chksums)
    extracted = false
    base = /.*(?=\.tar(?:\.\w+)?\z)/

    case mode
    when :download
      cache = do_download(url, cache_dir)
      do_checksum(cache, chksums)
    when :extract
      cache = cache_file(url, cache_dir)
      target = File.join(dest, File.basename(cache)[base])
      unless File.directory?(target)
        do_checksum(cache, chksums)
        extracted = do_extract(cache, dest)
      end
    when :all
      cache = do_download(url, cache_dir)
      target = File.join(dest, File.basename(cache)[base])
      unless File.directory?(target)
        do_checksum(cache, chksums)
        extracted = do_extract(cache, dest)
      end
    end
    extracted
  end

  def process(list)
    mode = @mode
    cache_dir = @cache_dir
    after_extract = (mode == :all or mode == :patch)
    success = true
    if $VERBOSE
      $stdout.puts "downloading for #{list}"
      $stdout.flush
    end
    vars = Vars.new
    extracted = false
    dest = File.dirname(list)
    url = chksums = nil
    IO.foreach(list) do |line|
      line.sub!(/\s*#.*/, '')
      if /^(\w+)\s*=\s*(.*)/ =~ line
        vars[$1] = vars.expand($2)
        next
      end
      if chksums
        chksums.concat(line.split)
      elsif /^\t/ =~ line
        if extracted and after_extract
          patch, *args = line.split.map {|s| vars.expand(s)}
          do_patch(dest, patch, args)
        end
        next
      elsif /^!\s*(?:chdir:\s*([^|\s]+)\|\s*)?(.*)/ =~ line
        if extracted and after_extract
          command = vars.expand($2.strip)
          chdir = $1 and chdir = vars.expand(chdir)
          do_exec(command, chdir, dest)
        end
        next
      elsif /->/ =~ line
        if extracted and after_extract
          link, file = $`.strip, $'.strip
          do_link(vars.expand(link), vars.expand(file), dest)
        end
        next
      else
        url, *chksums = line.split(' ')
      end
      if chksums.last == '\\'
        chksums.pop
        next
      end
      unless url
        chksums = nil
        next
      end
      url = vars.expand(url)
      begin
        extracted = do_command(mode, dest, url, cache_dir, chksums)
      rescue => e
        warn defined?(e.full_message) ? e.full_message : e.message
        success = false
      end
      url = chksums = nil
    end
    success
  end

  def process_under(dir)
    success = true
    Dir.glob("#{dir}/**/extlibs") do |list|
      success &= process(list)
    end
    success
  end

  def self.run(argv)
    cache_dir = nil
    mode = :all
    until argv.empty?
      case argv[0]
      when '--download'
        mode = :download
      when '--extract'
        mode = :extract
      when '--patch'
        mode = :patch
      when '--all'
        mode = :all
      when '--cache'
        argv.shift
        cache_dir = argv[0]
      when /\A--cache=/
        cache_dir = $'
      when '--'
        argv.shift
        break
      when /\A-/
        warn "unknown option: #{argv[0]}"
        return false
      else
        break
      end
      argv.shift
    end

    extlibs = new(mode, cache_dir: cache_dir)
    argv.inject(true) do |success, dir|
      success & extlibs.process_under(dir)
    end
  end
end

if $0 == __FILE__
  exit ExtLibs.run(ARGV)
end
