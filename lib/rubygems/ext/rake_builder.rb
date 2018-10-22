# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require "shellwords"

class Gem::Ext::RakeBuilder < Gem::Ext::Builder

  def self.build(extension, dest_path, results, args=[], lib_dir=nil)
    if File.basename(extension) =~ /mkrf_conf/i then
      cmd = "#{Gem.ruby} #{File.basename extension}".dup
      cmd << " #{args.join " "}" unless args.empty?
      run cmd, results
    end

    rake = ENV['rake']

    rake ||= begin
               "#{Gem.ruby} -rrubygems #{Gem.bin_path('rake', 'rake')}"
             rescue Gem::Exception
             end

    rake ||= Gem.default_exec_format % 'rake'

    rake_args = ["RUBYARCHDIR=#{dest_path}", "RUBYLIBDIR=#{dest_path}", *args]
    run "#{rake} #{rake_args.shelljoin}", results

    results
  end

end
