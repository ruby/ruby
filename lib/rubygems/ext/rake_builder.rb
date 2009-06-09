#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/ext/builder'
require 'rubygems/command'

class Gem::Ext::RakeBuilder < Gem::Ext::Builder

  def self.build(extension, directory, dest_path, results)
    if File.basename(extension) =~ /mkrf_conf/i then
      cmd = "#{Gem.ruby} #{File.basename extension}"
      cmd << " #{Gem::Command.build_args.join " "}" unless Gem::Command.build_args.empty?
      run cmd, results
    end

    # Deal with possible spaces in the path, e.g. C:/Program Files
    dest_path = '"' + dest_path + '"' if dest_path.include?(' ')

    cmd = ENV['rake'] || "#{Gem.ruby} -rubygems #{Gem.bin_path('rake')}" rescue Gem.default_exec_format % 'rake'
    cmd += " RUBYARCHDIR=#{dest_path} RUBYLIBDIR=#{dest_path}" # ENV is frozen

    run cmd, results

    results
  end

end

