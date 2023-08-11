# -*- ruby -*-
$VERBOSE = false
if (opt = ENV["RUBYOPT"]) and (opt = opt.dup).sub!(/(?:\A|\s)-w(?=\z|\s)/, '')
  ENV["RUBYOPT"] = opt
end
require "./rbconfig" unless defined?(RbConfig)
require_relative "../tool/test-coverage" if ENV.key?("COVERAGE")
load File.dirname(__FILE__) + '/ruby/default.mspec'
OBJDIR = File.expand_path("spec/ruby/optional/capi/ext")
class MSpecScript
  @testing_ruby = true

  builddir = Dir.pwd
  srcdir = ENV['SRCDIR']
  srcdir ||= File.read("Makefile", encoding: "US-ASCII")[/^\s*srcdir\s*=\s*(.+)/i, 1] rescue nil
  config = RbConfig::CONFIG

  # The default implementation to run the specs.
  set :target, File.join(builddir, "miniruby#{config['exeext']}")
  set :prefix, File.expand_path('ruby', File.dirname(__FILE__))
  if srcdir
    srcdir = File.expand_path(srcdir)
    set :flags, %W[
      -I#{srcdir}/lib
      #{srcdir}/tool/runruby.rb --archdir=#{builddir} --extout=#{config['EXTOUT']}
      --
    ]
  end

  if ENV.key?("COVERAGE")
    set :excludes, ["Coverage"]
  end
end

module MSpecScript::JobServer
  def cores(max = 1)
    if max > 1 and /(?:\A|\s)--jobserver-(?:auth|fds)=(\d+),(\d+)/ =~ ENV["MAKEFLAGS"]
      cores = 1
      begin
        r = IO.for_fd($1.to_i(10), "rb", autoclose: false)
        w = IO.for_fd($2.to_i(10), "wb", autoclose: false)
        jobtokens = r.read_nonblock(max - 1)
        cores = jobtokens.size
        if cores > 0
          cores += 1
          jobserver = w
          w = nil
          at_exit {
            jobserver.print(jobtokens)
            jobserver.close
          }
          MSpecScript::JobServer.module_eval do
            remove_method :cores
            define_method(:cores) do
              cores
            end
          end
          return cores
        end
      rescue Errno::EBADF
      ensure
        r&.close
        w&.close
      end
    end
    super
  end
end

class MSpecScript
  prepend JobServer
end

require 'mspec/runner/formatters/dotted'

class DottedFormatter
  prepend Module.new {
    BASE = __dir__ + "/ruby/"

    def initialize(out = nil)
      super
      if out
        @columns = nil
      else
        columns = ENV["COLUMNS"]&.to_i
        @columns = columns&.nonzero? || 80
      end
      @dotted = 0
      @loaded = false
      @count = 0
    end

    def register
      super
      MSpec.register :load, self
      MSpec.register :unload, self
    end

    def after(*)
      if @columns
        if @dotted == 0
          s = sprintf("%6d ", @count)
          print(s)
          @dotted += s.size
        end
        @count +=1
      end
      super
      if @columns and (@dotted += 1) >= @columns
        print "\n"
        @dotted = 0
      end
    end

    def load(*)
      file = MSpec.file || MSpec.files_array.first
      @loaded = true
      s = "#{file.delete_prefix(BASE)}:"
      print s
      if @columns
        if (@dotted += s.size) >= @columns
          print "\n"
          @dotted = 0
        else
          print " "
          @dotted += 1
        end
      end
      @count = 0
    end

    def unload
      super
      if @loaded
        print "\n" if @dotted > 0
        @dotted = 0
        @loaded = nil
      end
    end
  }
end
