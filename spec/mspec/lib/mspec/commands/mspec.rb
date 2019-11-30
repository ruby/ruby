#!/usr/bin/env ruby

require 'mspec/version'
require 'mspec/utils/options'
require 'mspec/utils/script'
require 'mspec/helpers/tmp'
require 'mspec/runner/actions/filter'
require 'mspec/runner/actions/timer'


class MSpecMain < MSpecScript
  def initialize
    super

    config[:loadpath] = []
    config[:requires] = []
    config[:target]   = ENV['RUBY'] || 'ruby'
    config[:flags]    = []
    config[:command]  = nil
    config[:options]  = []
    config[:launch]   = []
  end

  def options(argv = ARGV)
    config[:command] = argv.shift if ["ci", "run", "tag"].include?(argv[0])

    options = MSpecOptions.new "mspec [COMMAND] [options] (FILE|DIRECTORY|GLOB)+", 30, config

    options.doc " The mspec command sets up and invokes the sub-commands"
    options.doc " (see below) to enable, for instance, running the specs"
    options.doc " with different implementations like ruby, jruby, rbx, etc.\n"

    options.configure do |f|
      load f
      config[:options] << '-B' << f
    end

    options.targets

    options.on("--warnings", "Don't suppress warnings") do
      config[:flags] << '-w'
      ENV['OUTPUT_WARNINGS'] = '1'
    end

    options.on("-j", "--multi", "Run multiple (possibly parallel) subprocesses") do
      config[:multi] = true
    end

    options.version MSpec::VERSION do
      if config[:command]
        config[:options] << "-v"
      else
        puts "#{File.basename $0} #{MSpec::VERSION}"
        exit
      end
    end

    options.help do
      if config[:command]
        config[:options] << "-h"
      else
        puts options
        exit 1
      end
    end

    options.doc "\n Custom options"
    custom_options options

    # The rest of the help output
    options.doc "\n where COMMAND is one of:\n"
    options.doc "   run - Run the specified specs (default)"
    options.doc "   ci  - Run the known good specs"
    options.doc "   tag - Add or remove tags\n"
    options.doc " mspec COMMAND -h for more options\n"
    options.doc "   example: $ mspec run -h\n"

    options.on_extra { |o| config[:options] << o }
    options.parse(argv)

    if config[:multi]
      options = MSpecOptions.new "mspec", 30, config
      options.all
      patterns = options.parse(config[:options])
      @files = files_from_patterns(patterns)
    end
  end

  def register; end

  def multi_exec(argv)
    require 'mspec/runner/formatters/multi'
    formatter = config_formatter.extend(MultiFormatter)

    require 'mspec/runner/parallel'
    processes = cores(@files.size)
    ParallelRunner.new(@files, processes, formatter, argv).run
  end

  def run
    argv = config[:target].split(/\s+/)

    argv.concat config[:launch]
    argv.concat config[:flags]
    argv.concat config[:loadpath]
    argv.concat config[:requires]
    argv << "#{MSPEC_HOME}/bin/mspec-#{config[:command] || 'run'}"
    argv.concat config[:options]

    if config[:multi]
      exit multi_exec(argv)
    else
      $stderr.puts "$ #{argv.join(' ')}"
      $stderr.flush
      exec(*argv, close_others: false)
    end
  end
end
