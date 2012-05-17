#!/usr/bin/ruby
# Copyright:: Copyright 2012 Google Inc.
# License:: All Rights Reserved.
# Original Author:: Yugui Sonoda (mailto:yugui@google.com)
#
# Generates a runnable package of the pepper API example.

require File.join(File.dirname(__FILE__), 'nacl-config')
require 'json'
require 'find'
require 'fileutils'

include NaClConfig

class Installation
  include NaClConfig

  SRC_DIRS = [ Dir.pwd, HOST_LIB ]

  def initialize(destdir)
    @destdir = destdir
    @manifest = {
      "files" => {}
    }
    ruby_libs.each do |path|
      raise "Collision of #{path}" if @manifest['files'].key? path
      @manifest['files'][path] = {
        ARCH => {
          "url" => path
        }
      }
      if path[/\.so$/]
        alternate_path = path.gsub('/', "_")
        raise "Collision of #{alternate_path}" if @manifest['files'].key? alternate_path
        @manifest['files'][alternate_path] = {
          ARCH => {
            "url" => path
          }
        }
      end
    end
  end

  def manifest
    @manifest.dup
  end

  def install_program(basename)
    do_install_binary(basename, File.join(@destdir, "bin", ARCH))
    @manifest["program"] = {
      ARCH => {
        "url" => File.join("bin", ARCH, basename)
      }
    }
  end

  def install_library(name, basename)
    do_install_binary(basename, File.join(@destdir, "lib", ARCH))
    @manifest["files"][name] = {
      ARCH => {
        "url" => File.join("lib", ARCH, basename)
      }
    }
  end

  private
  def do_install_binary(basename, dest_dir)
    full_path = nil
    catch(:found) {
      SRC_DIRS.each do |path|
        full_path = File.join(path, basename)
        if File.exist? full_path
          throw :found
        end
      end
      raise Errno::ENOENT, "No such file to install: %s" % basename
    }
    FileUtils.mkdir_p dest_dir
    system("#{INSTALL_PROGRAM} #{full_path} #{dest_dir}")
  end

  def ruby_libs
    Find.find(RbConfig::CONFIG['rubylibdir']).select{|path| File.file?(path) }.map{|path| path.sub("#{@destdir}/", "") }
  end
end

def install(destdir)
  inst = Installation.new(destdir)
  manifest = JSON.parse(File.read("pepper-ruby.nmf"))

  program = File.basename(manifest['program'][ARCH]['url'])
  inst.install_program(program)

  manifest['files'].each do |name, attr|
    inst.install_library(name, File.basename(attr[ARCH]["url"]))
  end

  File.open(File.join(destdir, "ruby.nmf"), "w") {|f|
    f.puts JSON.pretty_generate(inst.manifest)
  }
end

def main
  install(ARGV[0])
end

if __FILE__ == $0
  main()
end
