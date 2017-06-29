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

  def options(argv=ARGV)
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

    options.on("--warnings", "Don't supress warnings") do
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
    MSpec.register_files @files

    require 'mspec/runner/formatters/multi'
    formatter = MultiFormatter.new
    if config[:formatter]
      warn "formatter options is ignored due to multi option"
    end

    output_files = []
    processes = cores(@files.size)
    children = processes.times.map { |i|
      name = tmp "mspec-multi-#{i}"
      output_files << name

      env = {
        "SPEC_TEMP_DIR" => "rubyspec_temp_#{i}",
        "MSPEC_MULTI" => i.to_s
      }
      command = argv + ["-fy", "-o", name]
      $stderr.puts "$ #{command.join(' ')}" if $MSPEC_DEBUG
      IO.popen([env, *command, close_others: false], "rb+")
    }

    puts children.map { |child| child.gets }.uniq
    formatter.start
    last_files = {}

    until @files.empty?
      IO.select(children)[0].each { |io|
        reply = io.read(1)
        case reply
        when '.'
          formatter.unload
        when nil
          raise "Worker died!"
        else
          while chunk = (io.read_nonblock(4096) rescue nil)
            reply += chunk
          end
          reply.chomp!('.')
          msg = "A child mspec-run process printed unexpected output on STDOUT"
          if last_file = last_files[io]
            msg += " while running #{last_file}"
          end
          abort "\n#{msg}: #{reply.inspect}"
        end

        unless @files.empty?
          file = @files.shift
          last_files[io] = file
          io.puts file
        end
      }
    end

    success = true
    children.each { |child|
      child.puts "QUIT"
      _pid, status = Process.wait2(child.pid)
      success &&= status.success?
      child.close
    }

    formatter.aggregate_results(output_files)
    formatter.finish
    success
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
      exec(*argv, close_others: false)
    end
  end
end
