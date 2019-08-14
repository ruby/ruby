# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

class Gem::Ext::ConfigureBuilder < Gem::Ext::Builder

  def self.build(extension, dest_path, results, args=[], lib_dir=nil)
    unless File.exist?('Makefile')
      cmd = "sh ./configure --prefix=#{dest_path}"
      cmd << " #{args.join ' '}" unless args.empty?

      run cmd, results
    end

    make dest_path, results

    results
  end

end
