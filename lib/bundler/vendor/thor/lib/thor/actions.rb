require_relative "actions/create_file"
require_relative "actions/create_link"
require_relative "actions/directory"
require_relative "actions/empty_directory"
require_relative "actions/file_manipulation"
require_relative "actions/inject_into_file"

class Bundler::Thor
  module Actions
    attr_accessor :behavior

    def self.included(base) #:nodoc:
      super(base)
      base.extend ClassMethods
    end

    module ClassMethods
      # Hold source paths for one Bundler::Thor instance. source_paths_for_search is the
      # method responsible to gather source_paths from this current class,
      # inherited paths and the source root.
      #
      def source_paths
        @_source_paths ||= []
      end

      # Stores and return the source root for this class
      def source_root(path = nil)
        @_source_root = path if path
        @_source_root ||= nil
      end

      # Returns the source paths in the following order:
      #
      #   1) This class source paths
      #   2) Source root
      #   3) Parents source paths
      #
      def source_paths_for_search
        paths = []
        paths += source_paths
        paths << source_root if source_root
        paths += from_superclass(:source_paths, [])
        paths
      end

      # Add runtime options that help actions execution.
      #
      def add_runtime_options!
        class_option :force, :type => :boolean, :aliases => "-f", :group => :runtime,
                             :desc => "Overwrite files that already exist"

        class_option :pretend, :type => :boolean, :aliases => "-p", :group => :runtime,
                               :desc => "Run but do not make any changes"

        class_option :quiet, :type => :boolean, :aliases => "-q", :group => :runtime,
                             :desc => "Suppress status output"

        class_option :skip, :type => :boolean, :aliases => "-s", :group => :runtime,
                            :desc => "Skip files that already exist"
      end
    end

    # Extends initializer to add more configuration options.
    #
    # ==== Configuration
    # behavior<Symbol>:: The actions default behavior. Can be :invoke or :revoke.
    #                    It also accepts :force, :skip and :pretend to set the behavior
    #                    and the respective option.
    #
    # destination_root<String>:: The root directory needed for some actions.
    #
    def initialize(args = [], options = {}, config = {})
      self.behavior = case config[:behavior].to_s
      when "force", "skip"
        _cleanup_options_and_set(options, config[:behavior])
        :invoke
      when "revoke"
        :revoke
      else
        :invoke
      end

      super
      self.destination_root = config[:destination_root]
    end

    # Wraps an action object and call it accordingly to the thor class behavior.
    #
    def action(instance) #:nodoc:
      if behavior == :revoke
        instance.revoke!
      else
        instance.invoke!
      end
    end

    # Returns the root for this thor class (also aliased as destination root).
    #
    def destination_root
      @destination_stack.last
    end

    # Sets the root for this thor class. Relatives path are added to the
    # directory where the script was invoked and expanded.
    #
    def destination_root=(root)
      @destination_stack ||= []
      @destination_stack[0] = File.expand_path(root || "")
    end

    # Returns the given path relative to the absolute root (ie, root where
    # the script started).
    #
    def relative_to_original_destination_root(path, remove_dot = true)
      root = @destination_stack[0]
      if path.start_with?(root) && [File::SEPARATOR, File::ALT_SEPARATOR, nil, ''].include?(path[root.size..root.size])
        path = path.dup
        path[0...root.size] = '.'
        remove_dot ? (path[2..-1] || "") : path
      else
        path
      end
    end

    # Holds source paths in instance so they can be manipulated.
    #
    def source_paths
      @source_paths ||= self.class.source_paths_for_search
    end

    # Receives a file or directory and search for it in the source paths.
    #
    def find_in_source_paths(file)
      possible_files = [file, file + TEMPLATE_EXTNAME]
      relative_root = relative_to_original_destination_root(destination_root, false)

      source_paths.each do |source|
        possible_files.each do |f|
          source_file = File.expand_path(f, File.join(source, relative_root))
          return source_file if File.exist?(source_file)
        end
      end

      message = "Could not find #{file.inspect} in any of your source paths. ".dup

      unless self.class.source_root
        message << "Please invoke #{self.class.name}.source_root(PATH) with the PATH containing your templates. "
      end

      message << if source_paths.empty?
                   "Currently you have no source paths."
                 else
                   "Your current source paths are: \n#{source_paths.join("\n")}"
                 end

      raise Error, message
    end

    # Do something in the root or on a provided subfolder. If a relative path
    # is given it's referenced from the current root. The full path is yielded
    # to the block you provide. The path is set back to the previous path when
    # the method exits.
    #
    # Returns the value yielded by the block.
    #
    # ==== Parameters
    # dir<String>:: the directory to move to.
    # config<Hash>:: give :verbose => true to log and use padding.
    #
    def inside(dir = "", config = {}, &block)
      verbose = config.fetch(:verbose, false)
      pretend = options[:pretend]

      say_status :inside, dir, verbose
      shell.padding += 1 if verbose
      @destination_stack.push File.expand_path(dir, destination_root)

      # If the directory doesnt exist and we're not pretending
      if !File.exist?(destination_root) && !pretend
        require "fileutils"
        FileUtils.mkdir_p(destination_root)
      end

      result = nil
      if pretend
        # In pretend mode, just yield down to the block
        result = block.arity == 1 ? yield(destination_root) : yield
      else
        require "fileutils"
        FileUtils.cd(destination_root) { result = block.arity == 1 ? yield(destination_root) : yield }
      end

      @destination_stack.pop
      shell.padding -= 1 if verbose
      result
    end

    # Goes to the root and execute the given block.
    #
    def in_root
      inside(@destination_stack.first) { yield }
    end

    # Loads an external file and execute it in the instance binding.
    #
    # ==== Parameters
    # path<String>:: The path to the file to execute. Can be a web address or
    #                a relative path from the source root.
    #
    # ==== Examples
    #
    #   apply "http://gist.github.com/103208"
    #
    #   apply "recipes/jquery.rb"
    #
    def apply(path, config = {})
      verbose = config.fetch(:verbose, true)
      is_uri  = path =~ %r{^https?\://}
      path    = find_in_source_paths(path) unless is_uri

      say_status :apply, path, verbose
      shell.padding += 1 if verbose

      contents = if is_uri
        require "open-uri"
        URI.open(path, "Accept" => "application/x-thor-template", &:read)
      else
        open(path, &:read)
      end

      instance_eval(contents, path)
      shell.padding -= 1 if verbose
    end

    # Executes a command returning the contents of the command.
    #
    # ==== Parameters
    # command<String>:: the command to be executed.
    # config<Hash>:: give :verbose => false to not log the status, :capture => true to hide to output. Specify :with
    #                to append an executable to command execution.
    #
    # ==== Example
    #
    #   inside('vendor') do
    #     run('ln -s ~/edge rails')
    #   end
    #
    def run(command, config = {})
      return unless behavior == :invoke

      destination = relative_to_original_destination_root(destination_root, false)
      desc = "#{command} from #{destination.inspect}"

      if config[:with]
        desc = "#{File.basename(config[:with].to_s)} #{desc}"
        command = "#{config[:with]} #{command}"
      end

      say_status :run, desc, config.fetch(:verbose, true)

      return if options[:pretend]

      env_splat = [config[:env]] if config[:env]

      if config[:capture]
        require "open3"
        result, status = Open3.capture2e(*env_splat, command.to_s)
        success = status.success?
      else
        result = system(*env_splat, command.to_s)
        success = result
      end

      abort if !success && config.fetch(:abort_on_failure, self.class.exit_on_failure?)

      result
    end

    # Executes a ruby script (taking into account WIN32 platform quirks).
    #
    # ==== Parameters
    # command<String>:: the command to be executed.
    # config<Hash>:: give :verbose => false to not log the status.
    #
    def run_ruby_script(command, config = {})
      return unless behavior == :invoke
      run command, config.merge(:with => Bundler::Thor::Util.ruby_command)
    end

    # Run a thor command. A hash of options can be given and it's converted to
    # switches.
    #
    # ==== Parameters
    # command<String>:: the command to be invoked
    # args<Array>:: arguments to the command
    # config<Hash>:: give :verbose => false to not log the status, :capture => true to hide to output.
    #                Other options are given as parameter to Bundler::Thor.
    #
    #
    # ==== Examples
    #
    #   thor :install, "http://gist.github.com/103208"
    #   #=> thor install http://gist.github.com/103208
    #
    #   thor :list, :all => true, :substring => 'rails'
    #   #=> thor list --all --substring=rails
    #
    def thor(command, *args)
      config  = args.last.is_a?(Hash) ? args.pop : {}
      verbose = config.key?(:verbose) ? config.delete(:verbose) : true
      pretend = config.key?(:pretend) ? config.delete(:pretend) : false
      capture = config.key?(:capture) ? config.delete(:capture) : false

      args.unshift(command)
      args.push Bundler::Thor::Options.to_switches(config)
      command = args.join(" ").strip

      run command, :with => :thor, :verbose => verbose, :pretend => pretend, :capture => capture
    end

  protected

    # Allow current root to be shared between invocations.
    #
    def _shared_configuration #:nodoc:
      super.merge!(:destination_root => destination_root)
    end

    def _cleanup_options_and_set(options, key) #:nodoc:
      case options
      when Array
        %w(--force -f --skip -s).each { |i| options.delete(i) }
        options << "--#{key}"
      when Hash
        [:force, :skip, "force", "skip"].each { |i| options.delete(i) }
        options.merge!(key => true)
      end
    end
  end
end
