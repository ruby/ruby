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

  def self.hack_for_obsolete_style_gems(directory)
    return unless directory and File.identical?(directory, ".")
    mf = Gem.read_binary 'Makefile'
    changed = false
    changed |= mf.gsub!(/^(install-rb-default:)(.*)/) {
      "#$1#{$2.gsub(/(?:^|\s+)\$\(RUBY(?:ARCH|LIB)DIR\)\/\S+(?=\s|$)/, '')}"
    }
    if changed
      File.open('Makefile', 'wb') {|f| f.print mf}
    end
  end

  def self.build(extension, directory, dest_path, results, args=[])
    siteconf = Tempfile.open(%w"siteconf .rb", ".") do |f|
      f.puts "require 'rbconfig'"
      f.puts "dest_path = #{dest_path.dump}"
      %w[sitearchdir sitelibdir].each do |dir|
        f.puts "RbConfig::MAKEFILE_CONFIG['#{dir}'] = dest_path"
        f.puts "RbConfig::CONFIG['#{dir}'] = dest_path"
      end
      f
    end

    rubyopt = ENV["RUBYOPT"]
    ENV["RUBYOPT"] = ["-r#{siteconf.path}", rubyopt].compact.join(' ')
    cmd = [Gem.ruby, File.basename(extension), *args].join ' '

    run cmd, results

    hack_for_obsolete_style_gems directory

    make dest_path, results

    results
  ensure
    ENV["RUBYOPT"] = rubyopt
    siteconf.close(true) if siteconf
  end

end

