#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/ext/builder'
require 'rubygems/command'
require 'fileutils'
require 'tempfile'

class Gem::Ext::ExtConfBuilder < Gem::Ext::Builder
  FileEntry = FileUtils::Entry_ # :nodoc:

  def self.build(extension, directory, dest_path, results, args=[])
    tmp_dest = Dir.mktmpdir(".gem.", ".")

    t = nil
    Tempfile.open %w"siteconf .rb", "." do |siteconf|
      t = siteconf
      siteconf.puts "require 'rbconfig'"
      siteconf.puts "dest_path = #{(tmp_dest || dest_path).dump}"
      %w[sitearchdir sitelibdir].each do |dir|
        siteconf.puts "RbConfig::MAKEFILE_CONFIG['#{dir}'] = dest_path"
        siteconf.puts "RbConfig::CONFIG['#{dir}'] = dest_path"
      end

      siteconf.flush

      siteconf_path = File.expand_path siteconf.path

      rubyopt = ENV["RUBYOPT"]
      destdir = ENV["DESTDIR"]

      begin
        ENV["RUBYOPT"] = ["-r#{siteconf_path}", rubyopt].compact.join(' ')
        cmd = [Gem.ruby, File.basename(extension), *args].join ' '

        run cmd, results

        ENV["DESTDIR"] = nil
        ENV["RUBYOPT"] = rubyopt
        siteconf.unlink

        make dest_path, results

        if tmp_dest
          FileEntry.new(tmp_dest).traverse do |ent|
            destent = ent.class.new(dest_path, ent.rel)
            destent.exist? or File.rename(ent.path, destent.path)
          end
        end
      ensure
        ENV["RUBYOPT"] = rubyopt
        ENV["DESTDIR"] = destdir
      end
    end
    t.unlink if t and t.path

    results
  ensure
    FileUtils.rm_rf tmp_dest if tmp_dest
  end

end

