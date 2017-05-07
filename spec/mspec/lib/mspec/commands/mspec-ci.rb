#!/usr/bin/env ruby

$:.unshift File.expand_path(File.dirname(__FILE__) + '/../lib')

require 'mspec/version'
require 'mspec/utils/options'
require 'mspec/utils/script'


class MSpecCI < MSpecScript
  def options(argv=ARGV)
    options = MSpecOptions.new "mspec ci [options] (FILE|DIRECTORY|GLOB)+", 30, config

    options.doc " Ask yourself:"
    options.doc "  1. How to run the specs?"
    options.doc "  2. How to modify the guard behavior?"
    options.doc "  2. How to display the output?"
    options.doc "  3. What action to perform?"
    options.doc "  4. When to perform it?"

    options.doc "\n How to run the specs"
    options.chdir
    options.prefix
    options.configure { |f| load f }
    options.name
    options.pretend
    options.interrupt

    options.doc "\n How to modify the guard behavior"
    options.unguarded
    options.verify

    options.doc "\n How to display their output"
    options.formatters
    options.verbose

    options.doc "\n What action to perform"
    options.actions

    options.doc "\n When to perform it"
    options.action_filters

    options.doc "\n Help!"
    options.debug
    options.version MSpec::VERSION
    options.help

    options.doc "\n Custom options"
    custom_options options

    options.doc "\n How might this work in the real world?"
    options.doc "\n   1. To simply run the known good specs"
    options.doc "\n     $ mspec ci"
    options.doc "\n   2. To run a subset of the known good specs"
    options.doc "\n     $ mspec ci path/to/specs"
    options.doc "\n   3. To start the debugger before the spec matching 'this crashes'"
    options.doc "\n     $ mspec ci --spec-debug -S 'this crashes'"
    options.doc ""

    patterns = options.parse argv
    patterns = config[:ci_files] if patterns.empty?
    @files = files patterns
  end

  def run
    MSpec.register_tags_patterns config[:tags_patterns]
    MSpec.register_files @files

    tags = ["fails", "critical", "unstable", "incomplete", "unsupported"]
    tags += Array(config[:ci_xtags])

    require 'mspec/runner/filters/tag'
    filter = TagFilter.new(:exclude, *tags)
    filter.register

    MSpec.process
    exit MSpec.exit_code
  end
end
