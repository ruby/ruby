# -*- ruby -*-
load "./rbconfig.rb"
load File.dirname(__FILE__) + '/rubyspec/default.mspec'
class MSpecScript
  builddir = Dir.pwd
  srcdir = ENV['SRCDIR']
  if !srcdir and File.exist?("#{builddir}/Makefile") then
    File.open("#{builddir}/Makefile", "r:US-ASCII") {|f|
      f.read[/^\s*srcdir\s*=\s*(.+)/i] and srcdir = $1
    }
  end
  config = RbConfig::CONFIG

  # The default implementation to run the specs.
  set :target, File.join(builddir, "miniruby#{config['exeext']}")
  set :prefix, File.expand_path('rubyspec', File.dirname(__FILE__))
  set :flags, %W[
    -I#{File.expand_path srcdir}/lib
    -I#{File.expand_path srcdir}
    -I#{File.expand_path srcdir}/#{config['EXTOUT']}/common
    #{File.expand_path srcdir}/tool/runruby.rb --archdir=#{Dir.pwd} --extout=#{config['EXTOUT']}
    --
  ]
end
