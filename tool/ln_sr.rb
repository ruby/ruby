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
unless respond_to?(:ln_sr)
  def ln_sr(src, dest, target_directory: true, force: nil, noop: nil, verbose: nil)
    options = "#{force ? 'f' : ''}#{target_directory ? '' : 'T'}"
    dest = File.path(dest)
    srcs = Array(src)
    link = proc do |s, target_dir_p = true|
      s = File.path(s)
      if target_dir_p
        d = File.join(destdirs = dest, File.basename(s))
      else
        destdirs = File.dirname(d = dest)
      end
      destdirs = fu_split_path(File.realpath(destdirs))
      if fu_starting_path?(s)
        srcdirs = fu_split_path((File.realdirpath(s) rescue File.expand_path(s)))
        base = fu_relative_components_from(srcdirs, destdirs)
        s = File.join(*base)
      else
        srcdirs = fu_clean_components(*fu_split_path(s))
        base = fu_relative_components_from(fu_split_path(Dir.pwd), destdirs)
        while srcdirs.first&. == ".." and base.last&.!=("..") and !fu_starting_path?(base.last)
          srcdirs.shift
          base.pop
        end
        s = File.join(*base, *srcdirs)
      end
      fu_output_message "ln -s#{options} #{s} #{d}" if verbose
      next if noop
      remove_file d, true if force
      File.symlink s, d
    end
    case srcs.size
    when 0
    when 1
      link[srcs[0], target_directory && File.directory?(dest)]
    else
      srcs.each(&link)
    end
  end

  def fu_split_path(path)
    path = File.path(path)
    list = []
    until (parent, base = File.split(path); parent == path or parent == ".")
      list << base
      path = parent
    end
    list << path
    list.reverse!
  end

  def fu_relative_components_from(target, base) #:nodoc:
    i = 0
    while target[i]&.== base[i]
      i += 1
    end
    Array.new(base.size-i, '..').concat(target[i..-1])
  end

  def fu_clean_components(*comp)
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
    def fu_starting_path?(path)
      path&.start_with?(%r(\w:|/))
    end
  else
    def fu_starting_path?(path)
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
