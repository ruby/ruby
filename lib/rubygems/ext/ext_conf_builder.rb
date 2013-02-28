#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/ext/builder'
require 'rubygems/command'
require 'fileutils'
require 'tmpdir'

class Gem::Ext::ExtConfBuilder < Gem::Ext::Builder

  def self.build(extension, directory, dest_path, results, args=[])
    pwd = Dir.pwd
    cmd = "#{Gem.ruby} -r./siteconf #{File.join pwd, File.basename(extension)}"
    cmd << " #{args.join ' '}" unless args.empty?

    Dir.mktmpdir("gem-install.") do |tmpdir|
      Dir.chdir(tmpdir) do
        open("siteconf.rb", "w") do |f|
          f.puts "require 'rbconfig'"
          f.puts "dest_path = #{dest_path.dump}"
          %w[sitearchdir sitelibdir].each do |dir|
            f.puts "RbConfig::MAKEFILE_CONFIG['#{dir}'] = dest_path"
            f.puts "RbConfig::CONFIG['#{dir}'] = dest_path"
          end
        end

        begin
          run cmd, results

          make dest_path, results
        ensure
          FileUtils.mv("mkmf.log", pwd) if $! and File.exist?("mkmf.log")
        end
      end
    end

    results
  end

end

