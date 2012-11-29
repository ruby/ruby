#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/ext/builder'

class Gem::Ext::ConfigureBuilder < Gem::Ext::Builder

  def self.build(extension, directory, dest_path, results, args=[])
    unless File.exist?('Makefile') then
      cmd = "sh ./configure --prefix=#{dest_path}"
      cmd << " #{args.join ' '}" unless args.empty?

      run cmd, results
    end

    make dest_path, results

    results
  end

end

