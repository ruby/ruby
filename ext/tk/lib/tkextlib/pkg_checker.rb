#!/usr/bin/env ruby
#
#  Ruby/Tk extension library checker
#
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

TkRoot.new.withdraw  # hide root window

name = File.basename(__FILE__)

if ARGV[0]
  dir = File.expand_path(ARGV[0])
else
  dir = File.dirname(File.expand_path(__FILE__))
end

print "\nRuby/Tk extension library checker\n"
print "( Note:: This check is very simple one. Shown status may be wrong. )\n"
print "\n check directory :: #{dir}\n"

def get_pkg_list(file)
  pkg_list = []

  File.foreach(file){|l|
    if l =~ /^(?:[^#]+\s|\s*)(?:|;\s*)TkPackage\s*\.\s*require\s*\(?\s*(["'])((\w|:)+)\1/
      pkg = [$2, :package]
      pkg_list << pkg unless pkg_list.member?(pkg)
    end
    if l =~ /^(?:[^#]+\s|\s*)(?:|;\s*)Tk\s*\.\s*load_tcllibrary\s*\(?\s*(["'])((\w|:)+)\1/
      pkg = [$2, :library]
      pkg_list << pkg unless pkg_list.member?(pkg)
    end
    if l =~ /^(?:[^#]+\s|\s*)(?:|;\s*)Tk\s*\.\s*load_tclscript\s*\(?\s*(["'])((\w|:)+)\1/
      pkg = [$2, :script]
      pkg_list << pkg unless pkg_list.member?(pkg)
    end
  }

  pkg_list
end

def check_pkg(file)
  pkg_list = get_pkg_list(file)

  error_list = []
  success_list = {}

  pkg_list.each{|name, type|
    next if success_list[name]

    begin
      case type
      when :package
	ver = TkPackage.require(name)
	success_list[name] = ver
	error_list.delete_if{|n, t| n == name}

      when :library
	Tk.load_tcllibrary(name)
	success_list[name] = :library
	error_list.delete_if{|n, t| n == name}

      when :script
	Tk.load_tclscript(name)
	success_list[name] = :script
	error_list.delete_if{|n, t| n == name}

      end
    rescue
      error_list << [name, type]
    end
  }

  success_list.dup.each{|name, ver|
    unless ver.kind_of?(String)
      begin
	ver = TkPackage.require(name)
	sccess_list[name] = ver
      rescue
      end
    end
  }

  [success_list, error_list]
end

def subdir_check(dir)
  Dir.foreach(dir){|f|
    next if f == '.' || f == '..'
    if File.directory?(f)
      subdir_check(File.join(dir, f))
    elsif File.extname(f) == '.rb'
      path = File.join(dir, f)
      suc, err = check_pkg(path)
      if err.empty?
	print 'Ready : ', path, ' : require->', suc.inspect, "\n"
      else
	print '*LACK : ', path, ' : require->', suc.inspect, 
	  '  FAIL->', err.inspect, "\n"
      end
    end
  }
end

Dir.chdir(dir)

(Dir['*.rb'] - ['setup.rb', name]).each{|f|
  subdir = File.basename(f, '.*')
  begin
    # read 'setup.rb' as if the library has standard structure
    require File.join(subdir, 'setup.rb')
  rescue LoadError
    # ignore error
  end

  print "\n"

  suc, err = check_pkg(f)
  if err.empty?
    print 'Ready : ', f, ' : require->', suc.inspect, "\n"
  else
    print '*LACK : ', f, ' : require->', suc.inspect, 
      '  FAIL->', err.inspect, "\n"
  end

  subdir_check(subdir) if File.directory?(subdir)
}
