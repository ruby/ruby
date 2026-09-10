# -*- ruby -*-
$VERBOSE = false
if (opt = ENV["RUBYOPT"]) and (opt = opt.dup).sub!(/(?:\A|\s)-w(?=\z|\s)/, '')
  ENV["RUBYOPT"] = opt
end
# The specs assert the output of the ruby processes they spawn verbatim.  See
# tool/test/init.rb for why the switch goes where it does.
rubyopt = ENV["RUBYOPT"].to_s.split - ["-W:no-experimental"]
rubyopt.insert(rubyopt.index("-") || rubyopt.size, "-W:no-experimental")
ENV["RUBYOPT"] = rubyopt.join(" ")

# Enable constant leak checks by ruby/mspec
ENV["CHECK_CONSTANT_LEAKS"] ||= "true"

require "./rbconfig" unless defined?(RbConfig)
require_relative "../tool/test-coverage" if ENV.key?("COVERAGE")
require_relative "../tool/lib/test/jobserver"
load File.dirname(__FILE__) + '/ruby/default.mspec'
OBJDIR = File.expand_path("spec/ruby/optional/capi/ext") unless defined?(OBJDIR)
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

  # Disable to run for bundled gems in test-spec
  set :bundled_gems, (File.readlines("#{srcdir}/gems/bundled_gems").map do |line|
    next if /^\s*(?:#|$)/ =~ line
    gem = line.split.first
    gem = "openstruct" if gem == "ostruct"
    "#{srcdir}/spec/ruby/library/#{gem}"
  end.compact)
  set :stdlibs, Dir.glob("#{srcdir}/spec/ruby/library/*")
  set :library, get(:stdlibs).to_a - get(:bundled_gems).to_a

  set :files, get(:command_line) + get(:language) + get(:core) + get(:library) + get(:security) + get(:optional)

  if ENV.key?("COVERAGE")
    set :excludes, ["Coverage"]
  end
end

module MSpecScript::JobServer
  def cores(max = 1)
    MSpecScript::JobServer.remove_method :cores
    if cores = Test::JobServer.max_jobs(max)
      MSpecScript::JobServer.define_method(:cores) { cores }
      return cores
    end
    super
  end
end

class MSpecScript
  prepend JobServer
end

if ENV["RUBY_BOX"] == "1"
  # Ruby::Box prints this at startup of every child process when RUBY_BOX=1
  # is inherited from the environment.
  module MSpecScript::StripBoxExperimentalWarning
    WARNING = /^.*: warning: Ruby::Box is experimental, and the behavior may change in the future!\nSee https:\/\/docs\.ruby-lang\.org\/\S+ for known issues, etc\.\n/

    # At load time this would resolve RUBY_EXE before mspec exports the flags.
    def setup_env
      super
      require "mspec/helpers/ruby_exe"
      Object.class_eval do
        # Not a prepend, which the Module ancestor specs would see.
        alias_method :ruby_exe_with_box_warning, :ruby_exe
        private :ruby_exe_with_box_warning

        private def ruby_exe(code = :not_given, opts = {})
          output = ruby_exe_with_box_warning(code, opts)
          if code != :not_given and !opts[:env]&.any? {|k,| k.to_s == "RUBY_BOX"}
            # on the bytes, since the output is not always valid in its encoding
            output = output.b.gsub(WARNING, "").force_encoding(output.encoding)
          end
          output
        end
      end
    end
  end

  class MSpecScript
    prepend StripBoxExperimentalWarning
  end
end

require 'mspec/runner/formatters/dotted'

class DottedFormatter
  prepend Module.new {
    BASE = __dir__ + "/ruby/" unless defined?(BASE)
    COUNT_WIDTH = 6 unless defined?(COUNT_WIDTH)

    def initialize(out = nil)
      super
      if out
        @columns = nil
      else
        columns = ENV["COLUMNS"]&.to_i
        columns = 80 unless columns&.nonzero?
        w = COUNT_WIDTH + 1
        round = 20
        @columns = (columns - w) / round * round + w
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
          s = sprintf("%*d ", COUNT_WIDTH, @count)
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
