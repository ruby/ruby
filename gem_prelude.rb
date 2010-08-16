# depends on: array.rb dir.rb env.rb file.rb hash.rb module.rb regexp.rb
# vim: filetype=ruby

# NOTICE: Ruby is during initialization here.
# * Encoding.default_external does not reflects -E.
# * Should not expect Encoding.default_internal.
# * Locale encoding is available.

if defined?(Gem) then

  # :stopdoc:

  module Kernel

    def gem(gem_name, *version_requirements)
      Gem::QuickLoader.load_full_rubygems_library
      gem gem_name, *version_requirements
    end
    private :gem
  end

  module Gem

    ConfigMap = {
      :EXEEXT            => RbConfig::CONFIG["EXEEXT"],
      :RUBY_SO_NAME      => RbConfig::CONFIG["RUBY_SO_NAME"],
      :arch              => RbConfig::CONFIG["arch"],
      :bindir            => RbConfig::CONFIG["bindir"],
      :libdir            => RbConfig::CONFIG["libdir"],
      :ruby_install_name => RbConfig::CONFIG["ruby_install_name"],
      :ruby_version      => RbConfig::CONFIG["ruby_version"],
      :rubylibprefix     => RbConfig::CONFIG["rubylibprefix"],
      :sitedir           => RbConfig::CONFIG["sitedir"],
      :sitelibdir        => RbConfig::CONFIG["sitelibdir"],
    }

    def self.suffixes
      ['', '.rb', ".#{RbConfig::CONFIG["DLEXT"]}"]
    end

    def self.dir
      @gem_home ||= nil
      set_home(ENV['GEM_HOME'] || default_dir) unless @gem_home
      @gem_home
    end

    def self.path
      @gem_path ||= nil
      unless @gem_path
        paths = [ENV['GEM_PATH'] || default_path]
        paths << APPLE_GEM_HOME if defined? APPLE_GEM_HOME
        set_paths(paths.compact.join(File::PATH_SEPARATOR))
      end
      @gem_path
    end

    def self.post_install(&hook)
      @post_install_hooks << hook
    end

    def self.post_uninstall(&hook)
      @post_uninstall_hooks << hook
    end

    def self.pre_install(&hook)
      @pre_install_hooks << hook
    end

    def self.pre_uninstall(&hook)
      @pre_uninstall_hooks << hook
    end

    def self.set_home(home)
      home = home.dup.force_encoding(Encoding.find('filesystem'))
      home.gsub!(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
      @gem_home = home
    end

    def self.set_paths(gpaths)
      if gpaths
        @gem_path = gpaths.split(File::PATH_SEPARATOR)

        if File::ALT_SEPARATOR then
          @gem_path.map! do |path|
            path.gsub File::ALT_SEPARATOR, File::SEPARATOR
          end
        end

        @gem_path << Gem.dir
      else
        # TODO: should this be Gem.default_path instead?
        @gem_path = [Gem.dir]
      end

      @gem_path.uniq!
      @gem_path.map!{|x|x.force_encoding(Encoding.find('filesystem'))}
    end

    def self.user_home
      @user_home ||= File.expand_path("~").force_encoding(Encoding.find('filesystem'))
    rescue
      if File::ALT_SEPARATOR then
        "C:/"
      else
        "/"
      end
    end

    # begin rubygems/defaults
    # NOTE: this require will be replaced with in-place eval before compilation.
    require 'lib/rubygems/defaults.rb'
    # end rubygems/defaults


    ##
    # Methods before this line will be removed when QuickLoader is replaced
    # with the real RubyGems

    GEM_PRELUDE_METHODS = Gem.methods(false)

    begin
      verbose, debug = $VERBOSE, $DEBUG
      $VERBOSE = $DEBUG = nil

      begin
        require 'rubygems/defaults/operating_system'
      rescue ::LoadError
      end

      if defined?(RUBY_ENGINE) then
        begin
          require "rubygems/defaults/#{RUBY_ENGINE}"
        rescue ::LoadError
        end
      end
    ensure
      $VERBOSE, $DEBUG = verbose, debug
    end

    module QuickLoader

      @loaded_full_rubygems_library = false

      def self.remove
        return if @loaded_full_rubygems_library

        @loaded_full_rubygems_library = true

        class << Gem
          undef_method(*Gem::GEM_PRELUDE_METHODS)
        end

        remove_method :const_missing
        remove_method :method_missing

        Kernel.module_eval do
          undef_method :gem if method_defined? :gem
        end
      end

      def self.load_full_rubygems_library
        return false if @loaded_full_rubygems_library

        remove

        $".delete path_to_full_rubygems_library
        if $".any? {|path| path.end_with?('/rubygems.rb')}
          raise LoadError, "another rubygems is already loaded from #{path}"
        end

        require 'rubygems'

        return true
      end

      def self.path_to_full_rubygems_library
        installed_path = File.join(Gem::ConfigMap[:rubylibprefix], Gem::ConfigMap[:ruby_version])
        if $:.include?(installed_path)
          return File.join(installed_path, 'rubygems.rb')
        else # e.g., on test-all
          $:.each do |dir|
            if File.exist?( path = File.join(dir, 'rubygems.rb') )
              return path
            end
          end
          raise LoadError, 'rubygems.rb'
        end
      end

      def const_missing(constant)
        QuickLoader.load_full_rubygems_library

        if Gem.const_defined?(constant) then
          Gem.const_get constant
        else
          super
        end
      end

      def method_missing(method, *args, &block)
        QuickLoader.load_full_rubygems_library
        super unless Gem.respond_to?(method)
        Gem.send(method, *args, &block)
      end
    end

    extend QuickLoader

    def self.try_activate(path)
      # This method is only hit when the custom require is hit the first time.
      # So we go off and dutifully load all of rubygems and retry the call
      # to Gem.try_activate. We retry because full rubygems replaces this
      # method with one that actually tries to find a gem for +path+ and load it.
      #
      # This is conditional because in the course of loading rubygems, the custom
      # require will call back into here before all of rubygems is loaded. So
      # we must not always retry the call. We only redo the call when
      # load_full_rubygems_library returns true, which it only does the first
      # time it's called.
      #
      if QuickLoader.load_full_rubygems_library
        return Gem.try_activate(path)
      end

      return false
    end

  end

  begin
    require 'lib/rubygems/custom_require.rb'
  rescue Exception => e
    puts "Error loading gem paths on load path in gem_prelude"
    puts e
    puts e.backtrace.join("\n")
  end

end

