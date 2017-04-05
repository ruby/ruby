# -*- ruby -*-
load "./rbconfig.rb"
load File.dirname(__FILE__) + '/rubyspec/default.mspec'
OBJDIR = File.expand_path("spec/rubyspec/optional/capi/ext")
class MSpecScript
  builddir = Dir.pwd
  srcdir = ENV['SRCDIR']
  if !srcdir and File.exist?("#{builddir}/Makefile") then
    File.open("#{builddir}/Makefile", "r:US-ASCII") {|f|
      f.read[/^\s*srcdir\s*=\s*(.+)/i] and srcdir = $1
    }
  end
  srcdir = File.expand_path(srcdir)
  config = RbConfig::CONFIG

  # The default implementation to run the specs.
  set :target, File.join(builddir, "miniruby#{config['exeext']}")
  set :prefix, File.expand_path('rubyspec', File.dirname(__FILE__))
  set :flags, %W[
    -I#{srcdir}/lib
    -I#{srcdir}
    -I#{srcdir}/#{config['EXTOUT']}/common
    #{srcdir}/tool/runruby.rb --archdir=#{Dir.pwd} --extout=#{config['EXTOUT']}
    --
  ]
end

class MSpecScript
  if /(?:\A|\s)--jobserver-(?:auth|fds)=(\d+),(\d+)/ =~ ENV["MAKEFLAGS"]
    begin
      r = IO.for_fd($1.to_i(10), "rb", autoclose: false)
      w = IO.for_fd($2.to_i(10), "wb", autoclose: false)
    rescue
      r.close if r
    else
      jobtokens = r.read_nonblock(1024)
      cores = jobtokens.size
      if cores > 0
        jobserver = w
        at_exit {
          jobserver.print(jobtokens)
          jobserver.close
        }
      end
      remove_method :cores
      define_method(:cores) do
        cores
      end
    end
  end
end
