######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/ext/builder'

class Gem::Ext::ConfigureBuilder < Gem::Ext::Builder

  def self.build(extension, directory, dest_path, results)
    unless File.exist?('Makefile') then
      cmd = "sh ./configure --prefix=#{dest_path}"
      cmd << " #{Gem::Command.build_args.join ' '}" unless Gem::Command.build_args.empty?

      run cmd, results
    end

    make dest_path, results

    results
  end

end

