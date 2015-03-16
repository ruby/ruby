#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'fileutils'
require 'tempfile'

class Gem::Ext::ExtConfBuilder < Gem::Ext::Builder
  FileEntry = FileUtils::Entry_ # :nodoc:

  def self.build(extension, directory, dest_path, results, args=[], lib_dir=nil)
    # relative path required as some versions of mktmpdir return an absolute
    # path which breaks make if it includes a space in the name
    tmp_dest = get_relative_path(Dir.mktmpdir(".gem.", "."))

    t = nil
    Tempfile.open %w"siteconf .rb", "." do |siteconf|
      t = siteconf
      siteconf.puts "require 'rbconfig'"
      siteconf.puts "dest_path = #{tmp_dest.dump}"
      %w[sitearchdir sitelibdir].each do |dir|
        siteconf.puts "RbConfig::MAKEFILE_CONFIG['#{dir}'] = dest_path"
        siteconf.puts "RbConfig::CONFIG['#{dir}'] = dest_path"
      end

      siteconf.flush

      destdir = ENV["DESTDIR"]

      begin
        cmd = [Gem.ruby, "-r", get_relative_path(siteconf.path), File.basename(extension), *args].join ' '

        begin
          run cmd, results
        ensure
          FileUtils.mv 'mkmf.log', dest_path if File.exist? 'mkmf.log'
          siteconf.unlink
        end

        ENV["DESTDIR"] = nil

        make dest_path, results

        if tmp_dest
          # TODO remove in RubyGems 3
          if Gem.install_extension_in_lib and lib_dir then
            FileUtils.mkdir_p lib_dir
            entries = Dir.entries(tmp_dest) - %w[. ..]
            entries = entries.map { |entry| File.join tmp_dest, entry }
            FileUtils.cp_r entries, lib_dir, :remove_destination => true
          end

          FileEntry.new(tmp_dest).traverse do |ent|
            destent = ent.class.new(dest_path, ent.rel)
            destent.exist? or FileUtils.mv(ent.path, destent.path)
          end
        end
      ensure
        ENV["DESTDIR"] = destdir
      end
    end
    t.unlink if t and t.path

    results
  ensure
    FileUtils.rm_rf tmp_dest if tmp_dest
  end

  private
  def self.get_relative_path(path)
    path[0..Dir.pwd.length-1] = '.' if path.start_with?(Dir.pwd)
    path
  end

end

