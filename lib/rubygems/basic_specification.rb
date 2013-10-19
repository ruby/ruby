##
# BasicSpecification is an abstract class which implements some common code
# used by both Specification and StubSpecification.

class Gem::BasicSpecification

  ##
  # The path this gemspec was loaded from.  This attribute is not persisted.

  attr_reader :loaded_from

  def self.default_specifications_dir
    File.join(Gem.default_dir, "specifications", "default")
  end

  ##
  # True when the gem has been activated

  def activated?
    raise NotImplementedError
  end

  ##
  # Returns the full path to the base gem directory.
  #
  # eg: /usr/local/lib/ruby/gems/1.8

  def base_dir
    return Gem.dir unless loaded_from
    @base_dir ||= if default_gem? then
                    File.dirname File.dirname File.dirname loaded_from
                  else
                    File.dirname File.dirname loaded_from
                  end
  end

  ##
  # Return true if this spec can require +file+.

  def contains_requirable_file? file
    build_extensions

    suffixes = Gem.suffixes

    full_require_paths.any? do |dir|
      base = "#{dir}/#{file}"
      suffixes.any? { |suf| File.file? "#{base}#{suf}" }
    end
  end

  def default_gem?
    loaded_from &&
      File.dirname(loaded_from) == self.class.default_specifications_dir
  end

  ##
  # The directory the named +extension+ was installed into after being built.
  #
  # Usage:
  #
  #   spec.extensions.each do |ext|
  #     puts spec.extension_install_dir ext
  #   end

  def extension_install_dir
    File.join base_dir, 'extensions', Gem::Platform.local.to_s,
              Gem.extension_api_version, full_name
  end

  def find_full_gem_path # :nodoc:
    # TODO: also, shouldn't it default to full_name if it hasn't been written?
    path = File.expand_path File.join(gems_dir, full_name)
    path.untaint
    path if File.directory? path
  end

  private :find_full_gem_path

  ##
  # The full path to the gem (install path + full name).

  def full_gem_path
    # TODO: This is a heavily used method by gems, so we'll need
    # to aleast just alias it to #gem_dir rather than remove it.
    @full_gem_path ||= find_full_gem_path
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

  ##
  # Full paths in the gem to add to <code>$LOAD_PATH</code> when this gem is
  # activated.

  def full_require_paths
    full_paths = @require_paths.map do |path|
      File.join full_gem_path, path
    end

    full_paths << extension_install_dir unless @extensions.empty?

    full_paths
  end

  ##
  # Returns the full path to this spec's gem directory.
  # eg: /usr/local/lib/ruby/1.8/gems/mygem-1.0

  def gem_dir
    @gem_dir ||= File.expand_path File.join(gems_dir, full_name)
  end

  ##
  # Returns the full path to the gems directory containing this spec's
  # gem directory. eg: /usr/local/lib/ruby/1.8/gems

  def gems_dir
    # TODO: this logic seems terribly broken, but tests fail if just base_dir
    @gems_dir ||= File.join(loaded_from && base_dir || Gem.dir, "gems")
  end

  ##
  # Set the path the Specification was loaded from. +path+ is converted to a
  # String.

  def loaded_from= path
    @loaded_from   = path && path.to_s

    @full_gem_path = nil
    @gems_dir      = nil
    @base_dir      = nil
  end

  ##
  # Name of the gem

  def name
    raise NotImplementedError
  end

  ##
  # Platform of the gem

  def platform
    raise NotImplementedError
  end

  ##
  # Paths in the gem to add to <code>$LOAD_PATH</code> when this gem is
  # activated.
  #
  # See also #require_paths=
  #
  # If you have an extension you do not need to add <code>"ext"</code> to the
  # require path, the extension build process will copy the extension files
  # into "lib" for you.
  #
  # The default value is <code>"lib"</code>
  #
  # Usage:
  #
  #   # If all library files are in the root directory...
  #   spec.require_path = '.'

  def require_paths
    return @require_paths if @extensions.empty?

    relative_extension_install_dir =
      File.join '..', '..', 'extensions', Gem::Platform.local.to_s,
                Gem.extension_api_version, full_name

    @require_paths + [relative_extension_install_dir]
  end

  ##
  # Return a Gem::Specification from this gem

  def to_spec
    raise NotImplementedError
  end

  ##
  # Version of the gem

  def version
    raise NotImplementedError
  end

end

