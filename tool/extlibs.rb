#!/usr/bin/ruby

# Used to download, extract and patch extension libraries (extlibs)
# for Ruby. See common.mk for Ruby's usage.

require 'digest'
require_relative 'downloader'

class ExtLibs
  def cache_file(url, cache_dir)
    Downloader.cache_file(url, nil, :cache_dir => cache_dir)
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
      if hd == sum
        if $VERBOSE
          $stdout.puts " OK"
          $stdout.flush
        end
      else
        if $VERBOSE
          $stdout.puts " NG"
          $stdout.flush
        end
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
    Process.wait(Process.spawn("patch", "-d", dest, "-i", patch, *args))
    $?.success? or raise "failed to patch #{patch}"
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

  def run(argv)
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

    success = true
    argv.each do |dir|
      Dir.glob("#{dir}/**/extlibs") do |list|
        if $VERBOSE
          $stdout.puts "downloading for #{list}"
          $stdout.flush
        end
        extracted = false
        dest = File.dirname(list)
        url = chksums = nil
        IO.foreach(list) do |line|
          line.sub!(/\s*#.*/, '')
          if chksums
            chksums.concat(line.split)
          elsif /^\t/ =~ line
            if extracted and (mode == :all or mode == :patch)
              patch, *args = line.split
              do_patch(dest, patch, args)
            end
            next
          else
            url, *chksums = line.split(' ')
          end
          if chksums.last == '\\'
            chksums.pop
            next
          end
          next unless url
          begin
            extracted = do_command(mode, dest, url, cache_dir, chksums)
          rescue => e
            warn e.inspect
            success = false
          end
          url = chksums = nil
        end
      end
    end
    success
  end

  def self.run(argv)
    self.new.run(argv)
  end
end

if $0 == __FILE__
  exit ExtLibs.run(ARGV)
end
