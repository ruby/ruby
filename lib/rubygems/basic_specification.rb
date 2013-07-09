module Gem
  # BasicSpecification is an abstract class which implements some common code used by
  # both Specification and StubSpecification.
  class BasicSpecification
    def self.default_specifications_dir
      File.join(Gem.default_dir, "specifications", "default")
    end

    ##
    # Name of the gem

    def name
      raise NotImplementedError
    end

    ##
    # Version of the gem

    def version
      raise NotImplementedError
    end

    ##
    # Platform of the gem

    def platform
      raise NotImplementedError
    end

    ##
    # Require paths of the gem

    def require_paths
      raise NotImplementedError
    end

    ##
    # True when the gem has been activated

    def activated?
      raise NotImplementedError
    end

    ##
    # Return a Gem::Specification from this gem

    def to_spec
      raise NotImplementedError
    end

    ##
    # The filename of the gem specification
    attr_reader :filename

    ##
    # Set the filename of the Specification was loaded from. +path+ is converted
    # to a String.

    def filename= path
      @filename      = path && path.to_s

      @full_gem_path = nil
      @gems_dir      = nil
      @base_dir      = nil
    end

    ##
    # Return true if this spec can require +file+.

    def contains_requirable_file? file
      root     = full_gem_path
      suffixes = Gem.suffixes

      require_paths.any? do |lib|
        base = "#{root}/#{lib}/#{file}"
        suffixes.any? { |suf| File.file? "#{base}#{suf}" }
      end
    end

    ##
    # The full path to the gem (install path + full name).

    def full_gem_path
      # TODO: This is a heavily used method by gems, so we'll need
      # to aleast just alias it to #gem_dir rather than remove it.
      @full_gem_path ||= find_full_gem_path
    end

    # :nodoc:
    def find_full_gem_path
      # TODO: also, shouldn't it default to full_name if it hasn't been written?
      path = File.expand_path File.join(gems_dir, full_name)
      path.untaint
      path if File.directory? path
    end
    private :find_full_gem_path

    ##
    # Returns the full path to the gems directory containing this spec's
    # gem directory. eg: /usr/local/lib/ruby/1.8/gems

    def gems_dir
      # TODO: this logic seems terribly broken, but tests fail if just base_dir
      @gems_dir ||= File.join(filename && base_dir || Gem.dir, "gems")
    end

    ##
    # Returns the full path to the base gem directory.
    #
    # eg: /usr/local/lib/ruby/gems/1.8

    def base_dir
      return Gem.dir unless filename
      @base_dir ||= if default_gem? then
                      File.dirname File.dirname File.dirname filename
                    else
                      File.dirname File.dirname filename
                    end
    end

    def default_gem?
      filename &&
        File.dirname(filename) == self.class.default_specifications_dir
    end

    ##
    # Returns the full name (name-version) of this Gem.  Platform information
    # is included (name-version-platform) if it is specified and not the
    # default Ruby platform.

    def full_name
      if platform == Gem::Platform::RUBY or platform.nil? then
        "#{name}-#{version}".untaint
      else
        "#{name}-#{version}-#{platform}".untaint
      end
    end
  end
end
