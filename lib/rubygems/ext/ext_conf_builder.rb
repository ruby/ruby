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
    cmd = "#{Gem.ruby} #{File.join pwd, File.basename(extension)}"
    cmd << " #{args.join ' '}" unless args.empty?

    Dir.mktmpdir("gem-install.") do |tmpdir|
      Dir.chdir(tmpdir) do
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

