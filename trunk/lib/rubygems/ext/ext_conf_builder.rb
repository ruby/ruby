#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/ext/builder'

class Gem::Ext::ExtConfBuilder < Gem::Ext::Builder

  def self.build(extension, directory, dest_path, results)
    cmd = "#{Gem.ruby} #{File.basename extension}"
    cmd << " #{ARGV.join ' '}" unless ARGV.empty?

    run cmd, results

    make dest_path, results

    results
  end

end

