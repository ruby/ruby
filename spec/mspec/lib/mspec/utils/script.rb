require 'mspec/guards/guard'
require 'mspec/guards/version'
require 'mspec/utils/warnings'

# MSpecScript provides a skeleton for all the MSpec runner scripts.

class MSpecScript
  # Returns the config object. Maintained at the class
  # level to easily enable simple config files. See the
  # class method +set+.
  def self.config
    @config ||= {
      :path => ['.', 'spec'],
      :config_ext => '.mspec'
    }
  end

  # Associates +value+ with +key+ in the config object. Enables
  # simple config files of the form:
  #
  #   class MSpecScript
  #     set :target, "ruby"
  #     set :files, ["one_spec.rb", "two_spec.rb"]
  #   end
  def self.set(key, value)
    config[key] = value
  end

  # Gets the value of +key+ from the config object. Simplifies
  # getting values in a config file:
  #
  #   class MSpecScript
  #     set :a, 1
  #     set :b, 2
  #     set :c, get(:a) + get(:b)
  #   end
  def self.get(key)
    config[key]
  end

  def initialize
    ruby_version_is ""..."2.2" do
      abort "MSpec needs Ruby 2.2 or more recent"
    end

    config[:formatter] = nil
    config[:includes]  = []
    config[:excludes]  = []
    config[:patterns]  = []
    config[:xpatterns] = []
    config[:tags]      = []
    config[:xtags]     = []
    config[:profiles]  = []
    config[:xprofiles] = []
    config[:atags]     = []
    config[:astrings]  = []
    config[:ltags]     = []
    config[:abort]     = true
    @loaded = []
  end

  # Returns the config object maintained by the instance's class.
  # See the class methods +set+ and +config+.
  def config
    MSpecScript.config
  end

  # Returns +true+ if the file was located in +config[:path]+,
  # possibly appending +config[:config_ext]. Returns +false+
  # otherwise.
  def try_load(target)
    names = [target]
    unless target[-6..-1] == config[:config_ext]
      names << target + config[:config_ext]
    end

    names.each do |name|
      config[:path].each do |dir|
        file = File.expand_path name, dir
        if @loaded.include?(file)
          return true
        elsif File.exist? file
          value = Kernel.load(file)
          @loaded << file
          return value
        end
      end
    end

    false
  end

  def load(target)
    try_load(target) or abort "Could not load config file #{target}"
  end

  # Attempts to load a default config file. First tries to load
  # 'default.mspec'. If that fails, attempts to load a config
  # file name constructed from the value of RUBY_ENGINE and the
  # first two numbers in RUBY_VERSION. For example, on MRI 1.8.6,
  # the file name would be 'ruby.1.8.mspec'.
  def load_default
    try_load 'default.mspec'

    if Object.const_defined?(:RUBY_ENGINE)
      engine = RUBY_ENGINE
    else
      engine = 'ruby'
    end
    try_load "#{engine}.#{SpecGuard.ruby_version}.mspec"
    try_load "#{engine}.mspec"
  end

  # Callback for enabling custom options. This version is a no-op.
  # Provide an implementation specific version in a config file.
  # Called by #options after the MSpec-provided options are added.
  def custom_options(options)
    options.doc "   No custom options registered"
  end

  # Registers all filters and actions.
  def register
    require 'mspec/runner/formatters/dotted'
    require 'mspec/runner/formatters/spinner'
    require 'mspec/runner/formatters/file'
    require 'mspec/runner/filters'

    if config[:formatter].nil?
      config[:formatter] = STDOUT.tty? ? SpinnerFormatter : @files.size < 50 ? DottedFormatter : FileFormatter
    end

    if config[:formatter]
      formatter = config[:formatter].new(config[:output])
      formatter.register
      MSpec.store :formatter, formatter
    end

    MatchFilter.new(:include, *config[:includes]).register    unless config[:includes].empty?
    MatchFilter.new(:exclude, *config[:excludes]).register    unless config[:excludes].empty?
    RegexpFilter.new(:include, *config[:patterns]).register   unless config[:patterns].empty?
    RegexpFilter.new(:exclude, *config[:xpatterns]).register  unless config[:xpatterns].empty?
    TagFilter.new(:include, *config[:tags]).register          unless config[:tags].empty?
    TagFilter.new(:exclude, *config[:xtags]).register         unless config[:xtags].empty?
    ProfileFilter.new(:include, *config[:profiles]).register  unless config[:profiles].empty?
    ProfileFilter.new(:exclude, *config[:xprofiles]).register unless config[:xprofiles].empty?

    DebugAction.new(config[:atags], config[:astrings]).register if config[:debugger]

    custom_register
  end

  # Callback for enabling custom actions, etc. This version is a
  # no-op. Provide an implementation specific version in a config
  # file. Called by #register.
  def custom_register
  end

  # Sets up signal handlers. Only a handler for SIGINT is
  # registered currently.
  def signals
    if config[:abort]
      Signal.trap "INT" do
        MSpec.actions :abort
        puts "\nProcess aborted!"
        exit! 1
      end
    end
  end

  # Attempts to resolve +partial+ as a file or directory name in the
  # following order:
  #
  #   1. +partial+
  #   2. +partial+ + "_spec.rb"
  #   3. <tt>File.join(config[:prefix], partial)</tt>
  #   4. <tt>File.join(config[:prefix], partial + "_spec.rb")</tt>
  #
  # If it is a file name, returns the name as an entry in an array.
  # If it is a directory, returns all *_spec.rb files in the
  # directory and subdirectories.
  #
  # If unable to resolve +partial+, +Kernel.abort+ is called.
  def entries(partial)
    file = partial + "_spec.rb"
    patterns = [partial, file]
    if config[:prefix]
      patterns << File.join(config[:prefix], partial)
      patterns << File.join(config[:prefix], file)
    end

    patterns.each do |pattern|
      expanded = File.expand_path(pattern)
      if File.file?(expanded) && expanded.end_with?('.rb')
        return [expanded]
      elsif File.directory?(expanded)
        specs = Dir["#{expanded}/**/*_spec.rb"].sort
        return specs unless specs.empty?
      end
    end

    abort "Could not find spec file #{partial}"
  end

  # Resolves each entry in +patterns+ to a set of files.
  #
  # If the pattern has a leading '^' character, the list of files
  # is subtracted from the list of files accumulated to that point.
  #
  # If the entry has a leading ':' character, the corresponding
  # key is looked up in the config object and the entries in the
  # value retrieved are processed through #entries.
  def files(patterns)
    list = []
    patterns.each do |pattern|
      case pattern[0]
      when ?^
        list -= entries(pattern[1..-1])
      when ?:
        key = pattern[1..-1].to_sym
        value = config[key]
        abort "Key #{pattern} not found in mspec config." unless value
        list += files(Array(value))
      else
        list += entries(pattern)
      end
    end
    list
  end

  def files_from_patterns(patterns)
    unless $0.end_with?("_spec.rb")
      if patterns.empty?
        patterns = config[:files]
      end
      if patterns.empty? and File.directory? "./spec"
        patterns = ["spec/"]
      end
    end
    list = files(patterns)
    abort "No files specified." if list.empty?
    list
  end

  def cores(max)
    require 'etc'
    [Etc.nprocessors, max].min
  end

  def setup_env
    ENV['MSPEC_RUNNER'] = '1'

    unless ENV['RUBY_EXE']
      ENV['RUBY_EXE'] = config[:target] if config[:target]
    end

    unless ENV['RUBY_FLAGS']
      ENV['RUBY_FLAGS'] = config[:flags].join(" ") if config[:flags]
    end
  end

  # Instantiates an instance and calls the series of methods to
  # invoke the script.
  def self.main
    script = new
    script.load_default
    script.try_load '~/.mspecrc'
    script.options
    script.signals
    script.register
    script.setup_env
    require 'mspec'
    script.run
  end
end
