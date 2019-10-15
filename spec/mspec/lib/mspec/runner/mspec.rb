require 'mspec/runner/context'
require 'mspec/runner/exception'
require 'mspec/runner/tag'

module MSpec
end

class MSpecEnv
  include MSpec
end

module MSpec

  @exit    = nil
  @abort   = nil
  @start   = nil
  @enter   = nil
  @before  = nil
  @add     = nil
  @after   = nil
  @leave   = nil
  @finish  = nil
  @exclude = nil
  @include = nil
  @leave   = nil
  @load    = nil
  @unload  = nil
  @tagged  = nil
  @current = nil
  @example = nil
  @modes   = []
  @shared  = {}
  @guarded = []
  @features     = {}
  @exception    = nil
  @randomize    = nil
  @repeat       = nil
  @expectation  = nil
  @expectations = false

  def self.describe(mod, options=nil, &block)
    state = ContextState.new mod, options
    state.parent = current

    MSpec.register_current state
    state.describe(&block)

    state.process unless state.shared? or current
  end

  def self.process
    STDOUT.puts RUBY_DESCRIPTION
    STDOUT.flush

    actions :start
    files
    actions :finish
  end

  def self.each_file(&block)
    if ENV["MSPEC_MULTI"]
      while file = STDIN.gets
        file = file.chomp
        return if file == "QUIT"
        yield file
        begin
          STDOUT.print "."
          STDOUT.flush
        rescue Errno::EPIPE
          # The parent died
          exit 1
        end
      end
      # The parent closed the connection without QUIT
      abort "the parent did not send QUIT"
    else
      return unless files = retrieve(:files)
      shuffle files if randomize?
      files.each(&block)
    end
  end

  def self.files
    each_file do |file|
      setup_env
      store :file, file
      actions :load
      protect("loading #{file}") { Kernel.load file }
      actions :unload
    end
  end

  def self.setup_env
    @env = MSpecEnv.new
  end

  def self.actions(action, *args)
    actions = retrieve(action)
    actions.each { |obj| obj.send action, *args } if actions
  end

  def self.protect(location, &block)
    begin
      @env.instance_eval(&block)
      return true
    rescue SystemExit => e
      raise e
    rescue SkippedSpecError => e
      return false
    rescue Exception => exc
      register_exit 1
      actions :exception, ExceptionState.new(current && current.state, location, exc)
      return false
    end
  end

  # Guards can be nested, so a stack is necessary to know when we have
  # exited the toplevel guard.
  def self.guard
    @guarded << true
  end

  def self.unguard
    @guarded.pop
  end

  def self.guarded?
    !@guarded.empty?
  end

  # Sets the toplevel ContextState to +state+.
  def self.register_current(state)
    store :current, state
  end

  # Sets the toplevel ContextState to +nil+.
  def self.clear_current
    store :current, nil
  end

  # Returns the toplevel ContextState.
  def self.current
    retrieve :current
  end

  # Stores the shared ContextState keyed by description.
  def self.register_shared(state)
    @shared[state.to_s] = state
  end

  # Returns the shared ContextState matching description.
  def self.retrieve_shared(desc)
    @shared[desc.to_s]
  end

  # Stores the exit code used by the runner scripts.
  def self.register_exit(code)
    store :exit, code
  end

  # Retrieves the stored exit code.
  def self.exit_code
    retrieve(:exit).to_i
  end

  # Stores the list of files to be evaluated.
  def self.register_files(files)
    store :files, files
  end

  # Stores one or more substitution patterns for transforming
  # a spec filename into a tags filename, where each pattern
  # has the form:
  #
  #   [Regexp, String]
  #
  # See also +tags_file+.
  def self.register_tags_patterns(patterns)
    store :tags_patterns, patterns
  end

  # Registers an operating mode. Modes recognized by MSpec:
  #
  #   :pretend - actions execute but specs are not run
  #   :verify - specs are run despite guards and the result is
  #             verified to match the expectation of the guard
  #   :report - specs that are guarded are reported
  #   :unguarded - all guards are forced off
  def self.register_mode(mode)
    modes = retrieve :modes
    modes << mode unless modes.include? mode
  end

  # Clears all registered modes.
  def self.clear_modes
    store :modes, []
  end

  # Returns +true+ if +mode+ is registered.
  def self.mode?(mode)
    retrieve(:modes).include? mode
  end

  def self.enable_feature(feature)
    retrieve(:features)[feature] = true
  end

  def self.disable_feature(feature)
    retrieve(:features)[feature] = false
  end

  def self.feature_enabled?(feature)
    retrieve(:features)[feature] || false
  end

  def self.retrieve(symbol)
    instance_variable_get :"@#{symbol}"
  end

  def self.store(symbol, value)
    instance_variable_set :"@#{symbol}", value
  end

  # This method is used for registering actions that are
  # run at particular points in the spec cycle:
  #   :start        before any specs are run
  #   :load         before a spec file is loaded
  #   :enter        before a describe block is run
  #   :before       before a single spec is run
  #   :add          while a describe block is adding examples to run later
  #   :expectation  before a 'should', 'should_receive', etc.
  #   :example      after an example block is run, passed the block
  #   :exception    after an exception is rescued
  #   :after        after a single spec is run
  #   :leave        after a describe block is run
  #   :unload       after a spec file is run
  #   :finish       after all specs are run
  #
  # Objects registered as actions above should respond to
  # a method of the same name. For example, if an object
  # is registered as a :start action, it should respond to
  # a #start method call.
  #
  # Additionally, there are two "action" lists for
  # filtering specs:
  #   :include  return true if the spec should be run
  #   :exclude  return true if the spec should NOT be run
  #
  def self.register(symbol, action)
    unless value = retrieve(symbol)
      value = store symbol, []
    end
    value << action unless value.include? action
  end

  def self.unregister(symbol, action)
    if value = retrieve(symbol)
      value.delete action
    end
  end

  def self.randomize(flag=true)
    @randomize = flag
  end

  def self.randomize?
    @randomize == true
  end

  def self.repeat=(times)
    @repeat = times
  end

  def self.repeat
    (@repeat || 1).times do
      yield
    end
  end

  def self.shuffle(ary)
    return if ary.empty?

    size = ary.size
    size.times do |i|
      r = rand(size - i - 1)
      ary[i], ary[r] = ary[r], ary[i]
    end
  end

  # Records that an expectation has been encountered in an example.
  def self.expectation
    store :expectations, true
  end

  # Returns true if an expectation has been encountered
  def self.expectation?
    retrieve :expectations
  end

  # Resets the flag that an expectation has been encountered in an example.
  def self.clear_expectations
    store :expectations, false
  end

  # Transforms a spec filename into a tags filename by applying each
  # substitution pattern in :tags_pattern. The default patterns are:
  #
  #   [%r(/spec/), '/spec/tags/'], [/_spec.rb$/, '_tags.txt']
  #
  # which will perform the following transformation:
  #
  #   path/to/spec/class/method_spec.rb => path/to/spec/tags/class/method_tags.txt
  #
  # See also +register_tags_patterns+.
  def self.tags_file
    patterns = retrieve(:tags_patterns) ||
               [[%r(spec/), 'spec/tags/'], [/_spec.rb$/, '_tags.txt']]
    patterns.inject(retrieve(:file).dup) do |file, pattern|
      file.gsub(*pattern)
    end
  end

  # Returns a list of tags matching any tag string in +keys+ based
  # on the return value of <tt>keys.include?("tag_name")</tt>
  def self.read_tags(keys)
    tags = []
    file = tags_file
    if File.exist? file
      File.open(file, "r:utf-8") do |f|
        f.each_line do |line|
          line.chomp!
          next if line.empty?
          tag = SpecTag.new line
          tags << tag if keys.include? tag.tag
        end
      end
    end
    tags
  end

  def self.make_tag_dir(path)
    parent = File.dirname(path)
    return if File.exist? parent
    begin
      Dir.mkdir(parent)
    rescue SystemCallError
      make_tag_dir(parent)
      Dir.mkdir(parent)
    end
  end

  # Writes each tag in +tags+ to the tag file. Overwrites the
  # tag file if it exists.
  def self.write_tags(tags)
    file = tags_file
    make_tag_dir(file)
    File.open(file, "w:utf-8") do |f|
      tags.each { |t| f.puts t }
    end
  end

  # Writes +tag+ to the tag file if it does not already exist.
  # Returns +true+ if the tag is written, +false+ otherwise.
  def self.write_tag(tag)
    tags = read_tags([tag.tag])
    tags.each do |t|
      if t.tag == tag.tag and t.description == tag.description
        return false
      end
    end

    file = tags_file
    make_tag_dir(file)
    File.open(file, "a:utf-8") { |f| f.puts tag.to_s }
    return true
  end

  # Deletes +tag+ from the tag file if it exists. Returns +true+
  # if the tag is deleted, +false+ otherwise. Deletes the tag
  # file if it is empty.
  def self.delete_tag(tag)
    deleted = false
    desc = tag.escape(tag.description)
    file = tags_file
    if File.exist? file
      lines = IO.readlines(file)
      File.open(file, "w:utf-8") do |f|
        lines.each do |line|
          line = line.chomp
          if line.start_with?(tag.tag) and line.end_with?(desc)
            deleted = true
          else
            f.puts line unless line.empty?
          end
        end
      end
      File.delete file unless File.size? file
    end
    return deleted
  end

  # Removes the tag file associated with a spec file.
  def self.delete_tags
    file = tags_file
    File.delete file if File.exist? file
  end

  # Initialize @env
  setup_env
end
