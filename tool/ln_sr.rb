#!/usr/bin/ruby

until ARGV.empty?
  case ARGV[0]
  when '-n'
    noop = true
  when '-f'
    force = true
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
  def ln_sr(src, dest, force: nil, noop: nil, verbose: nil)
    dest = File.path(dest)
    srcs = Array.try_convert(src) || [src]
    link = proc do |s, target_directory = true|
      s = File.path(s)
      if fu_starting_path?(s)
        srcdirs = fu_split_path((File.realdirpath(s) rescue File.expand_path(s)))
      else
        srcdirs = fu_clean_components(*fu_split_path(s))
      end
      destdirs = fu_split_path(File.realdirpath(dest))
      destdirs.pop unless target_directory
      base = fu_relative_components_from(fu_split_path(Dir.pwd), destdirs)
      while srcdirs.first&. == ".." and base.last and !fu_starting_path?(base.last)
        srcdirs.shift
        base.pop
      end
      s = File.join(*base, *srcdirs)
      d = target_directory ? File.join(dest, File.basename(s)) : dest
      fu_output_message "ln -s#{force ? 'f' : ''} #{s} #{d}" if verbose
      next if noop
      remove_file d, true if force
      File.symlink s, d
    end
    case srcs.size
    when 0
    when 1
      link[srcs[0], File.directory?(dest)]
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
        path.chomp!(%r((?<=\A|/)[^/]+/\z), "")
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
  begin
    ln_sr(src, dest, verbose: true, force: force, noop: noop)
  rescue NotImplementedError, Errno::EPERM
  else
    exit
  end
end

cp_r(src, dest)
