#!/usr/bin/env ruby

require 'mspec/version'
require 'mspec/utils/options'
require 'mspec/utils/script'


class MSpecTag < MSpecScript
  def initialize
    super

    config[:tagger]  = :add
    config[:tag]     = 'fails:'
    config[:outcome] = :fail
    config[:ltags]   = []
  end

  def options(argv=ARGV)
    options = MSpecOptions.new "mspec tag [options] (FILE|DIRECTORY|GLOB)+", 30, config

    options.doc " Ask yourself:"
    options.doc "  1. What specs to run?"
    options.doc "  2. How to modify the execution?"
    options.doc "  3. How to display the output?"
    options.doc "  4. What tag action to perform?"
    options.doc "  5. When to perform it?"

    options.doc "\n What specs to run"
    options.filters

    options.doc "\n How to modify the execution"
    options.configure { |f| load f }
    options.pretend
    options.unguarded
    options.interrupt

    options.doc "\n How to display their output"
    options.formatters
    options.verbose

    options.doc "\n What action to perform and when to perform it"
    options.on("-N", "--add", "TAG",
       "Add TAG with format 'tag' or 'tag(comment)' (see -Q, -F, -L)") do |o|
      config[:tagger] = :add
      config[:tag] = "#{o}:"
    end
    options.on("-R", "--del", "TAG",
       "Delete TAG (see -Q, -F, -L)") do |o|
      config[:tagger] = :del
      config[:tag] = "#{o}:"
      config[:outcome] = :pass
    end
    options.on("-Q", "--pass", "Apply action to specs that pass (default for --del)") do
      config[:outcome] = :pass
    end
    options.on("-F", "--fail", "Apply action to specs that fail (default for --add)") do
      config[:outcome] = :fail
    end
    options.on("-L", "--all", "Apply action to all specs") do
      config[:outcome] = :all
    end
    options.on("--list", "TAG", "Display descriptions of any specs tagged with TAG") do |t|
      config[:tagger] = :list
      config[:ltags] << t
    end
    options.on("--list-all", "Display descriptions of any tagged specs") do
      config[:tagger] = :list_all
    end
    options.on("--purge", "Remove all tags not matching any specs") do
      config[:tagger] = :purge
    end

    options.doc "\n Help!"
    options.debug
    options.version MSpec::VERSION
    options.help

    options.doc "\n Custom options"
    custom_options options

    options.doc "\n How might this work in the real world?"
    options.doc "\n   1. To add the 'fails' tag to failing specs"
    options.doc "\n     $ mspec tag path/to/the_file_spec.rb"
    options.doc "\n   2. To remove the 'fails' tag from passing specs"
    options.doc "\n     $ mspec tag --del fails path/to/the_file_spec.rb"
    options.doc "\n   3. To display the descriptions for all specs tagged with 'fails'"
    options.doc "\n     $ mspec tag --list fails path/to/the/specs"
    options.doc ""

    patterns = options.parse argv
    if patterns.empty?
      puts options
      puts "No files specified."
      exit 1
    end
    @files = files patterns
  end

  def register
    require 'mspec/runner/actions'

    case config[:tagger]
    when :add, :del
      tag = SpecTag.new config[:tag]
      tagger = TagAction.new(config[:tagger], config[:outcome], tag.tag, tag.comment,
                             config[:atags], config[:astrings])
    when :list, :list_all
      tagger = TagListAction.new config[:tagger] == :list_all ? nil : config[:ltags]
      MSpec.register_mode :pretend
      config[:formatter] = false
    when :purge
      tagger = TagPurgeAction.new
      MSpec.register_mode :pretend
      MSpec.register_mode :unguarded
      config[:formatter] = false
    else
      raise ArgumentError, "No recognized action given"
    end
    tagger.register

    super
  end

  def run
    MSpec.register_tags_patterns config[:tags_patterns]
    MSpec.register_files @files

    MSpec.process
    exit MSpec.exit_code
  end
end

