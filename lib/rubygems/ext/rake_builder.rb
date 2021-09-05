# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

class Gem::Ext::RakeBuilder < Gem::Ext::Builder
  def self.build(extension, dest_path, results, args=[], lib_dir=nil, extension_dir=Dir.pwd)
    if File.basename(extension) =~ /mkrf_conf/i
      run([Gem.ruby, File.basename(extension), *args], results, class_name, extension_dir)
    end

    rake = ENV['rake']

    if rake
      require "shellwords"
      rake = rake.shellsplit
    else
      begin
        rake = [Gem.ruby, "-I#{File.expand_path("../..", __dir__)}", "-rrubygems", Gem.bin_path('rake', 'rake')]
      rescue Gem::Exception
        rake = [Gem.default_exec_format % 'rake']
      end
    end

    rake_args = ["RUBYARCHDIR=#{dest_path}", "RUBYLIBDIR=#{dest_path}", *args]
    run(rake + rake_args, results, class_name, extension_dir)

    results
  end
end
