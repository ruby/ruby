#!/usr/bin/ruby

target_directory = true
noop = false
force = false
quiet = false

until ARGV.empty?
  case ARGV[0]
  when '-n'
    noop = true
  when '-f'
    force = true
  when '-T'
    target_directory = false
  when '-q'
    quiet = true
  else
    break
  end
  ARGV.shift
end

unless ARGV.size == 2
  abort "usage: #{$0} src destdir"
end
src, dest = ARGV

require 'fileutils'

include FileUtils
unless respond_to?(:ln_sr, true)
  def ln_sr(src, dest, target_directory: true, force: nil, noop: nil, verbose: nil)
    cmd = "ln -s#{force ? 'f' : ''}#{target_directory ? '' : 'T'}" if verbose
    fu_each_src_dest0(src, dest, target_directory) do |s,d|
      if target_directory
        parent = File.dirname(d)
        destdirs = fu_split_path(parent)
        real_ddirs = fu_split_path(File.realpath(parent))
      else
        destdirs ||= fu_split_path(dest)
        real_ddirs ||= fu_split_path(File.realdirpath(dest))
      end
      srcdirs = fu_split_path(s)
      i = fu_common_components(srcdirs, destdirs)
      n = destdirs.size - i
      n -= 1 unless target_directory
      link1 = fu_clean_components(*Array.new([n, 0].max, '..'), *srcdirs[i..-1])
      begin
        real_sdirs = fu_split_path(File.realdirpath(s)) rescue nil
      rescue
      else
        i = fu_common_components(real_sdirs, real_ddirs)
        n = real_ddirs.size - i
        n -= 1 unless target_directory
        link2 = fu_clean_components(*Array.new([n, 0].max, '..'), *real_sdirs[i..-1])
        link1 = link2 if link1.size > link2.size
      end
      s = File.join(link1)
      fu_output_message [cmd, s, d].flatten.join(' ') if verbose
      next if noop
      remove_file d, true if force
      File.symlink s, d
    end
  end

  def fu_split_path(path) #:nodoc:
    path = File.path(path)
    list = []
    until (parent, base = File.split(path); parent == path or parent == ".")
      if base != '..' and list.last == '..' and !(fu_have_symlink? && File.symlink?(path))
        list.pop
      else
        list << base
      end
      path = parent
    end
    list << path
    list.reverse!
  end

  def fu_common_components(target, base) #:nodoc:
    i = 0
    while target[i]&.== base[i]
      i += 1
    end
    i
  end

  def fu_clean_components(*comp) #:nodoc:
    comp.shift while comp.first == "."
    return comp if comp.empty?
    clean = [comp.shift]
    path = File.join(*clean, "") # ending with File::SEPARATOR
    while c = comp.shift
      if c == ".." and clean.last != ".." and !(fu_have_symlink? && File.symlink?(path))
        clean.pop
        path.sub!(%r((?<=\A|/)[^/]+/\z), "")
      else
        clean << c
        path << c << "/"
      end
    end
    clean
  end

  if fu_windows?
    def fu_starting_path?(path) #:nodoc:
      path&.start_with?(%r(\w:|/))
    end
  else
    def fu_starting_path?(path) #:nodoc:
      path&.start_with?("/")
    end
  end
end

if File.respond_to?(:symlink)
  if quiet and File.identical?(src, dest)
    exit
  end
  begin
    ln_sr(src, dest, verbose: true, target_directory: target_directory, force: force, noop: noop)
  rescue NotImplementedError, Errno::EPERM, Errno::EACCES
  else
    exit
  end
end

cp_r(src, dest)
