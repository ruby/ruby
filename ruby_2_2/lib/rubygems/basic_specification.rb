##
# BasicSpecification is an abstract class which implements some common code
# used by both Specification and StubSpecification.

class Gem::BasicSpecification

  ##
  # Allows installation of extensions for git: gems.

  attr_writer :base_dir # :nodoc:

  ##
  # Sets the directory where extensions for this gem will be installed.

  attr_writer :extension_dir # :nodoc:

  ##
  # Is this specification ignored for activation purposes?

  attr_writer :ignored # :nodoc:

  ##
  # The path this gemspec was loaded from.  This attribute is not persisted.

  attr_reader :loaded_from

  ##
  # Allows correct activation of git: and path: gems.

  attr_writer :full_gem_path # :nodoc:

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
    @contains_requirable_file ||= {}
    @contains_requirable_file[file] ||=
    begin
      if instance_variable_defined?(:@ignored) or
         instance_variable_defined?('@ignored') then
        return false
      elsif missing_extensions? then
        @ignored = true

        warn "Ignoring #{full_name} because its extensions are not built.  " +
             "Try: gem pristine #{name} --version #{version}"
        return false
      end

      suffixes = Gem.suffixes

      full_require_paths.any? do |dir|
        base = "#{dir}/#{file}"
        suffixes.any? { |suf| File.file? "#{base}#{suf}" }
      end
    end ? :yes : :no
    @contains_requirable_file[file] == :yes
  end

  def default_gem?
    loaded_from &&
      File.dirname(loaded_from) == self.class.default_specifications_dir
  end

  ##
  # Returns full path to the directory where gem's extensions are installed.

  def extension_dir
    @extension_dir ||= File.expand_path File.join(extensions_dir, full_name)
  end

  ##
  # Returns path to the extensions directory.

  def extensions_dir
    @extensions_dir ||= Gem.default_ext_dir_for(base_dir) ||
      File.join(base_dir, 'extensions', Gem::Platform.local.to_s,
                Gem.extension_api_version)
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
    @full_require_paths ||=
    begin
      full_paths = raw_require_paths.map do |path|
        File.join full_gem_path, path
      end

      full_paths.unshift extension_dir unless @extensions.nil? || @extensions.empty?

      full_paths
    end
  end

  ##
  # Full path of the target library file.
  # If the file is not in this gem, return nil.

  def to_fullpath path
    if activated? then
      @paths_map ||= {}
      @paths_map[path] ||=
      begin
        fullpath = nil
        suffixes = Gem.suffixes
        full_require_paths.find do |dir|
          suffixes.find do |suf|
            File.file?(fullpath = "#{dir}/#{path}#{suf}")
          end
        end ? fullpath : nil
      end
    else
      nil
    end
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

    @extension_dir = nil
    @extensions_dir = nil
    @full_gem_path         = nil
    @gem_dir               = nil
    @gems_dir              = nil
    @base_dir              = nil
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

  def raw_require_paths # :nodoc:
    Array(@require_paths)
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
    return raw_require_paths if @extensions.nil? || @extensions.empty?

    [extension_dir].concat raw_require_paths
  end

  ##
  # Returns the paths to the source files for use with analysis and
  # documentation tools.  These paths are relative to full_gem_path.

  def source_paths
    paths = raw_require_paths.dup

    if @extensions then
      ext_dirs = @extensions.map do |extension|
        extension.split(File::SEPARATOR, 2).first
      end.uniq

      paths.concat ext_dirs
    end

    paths.uniq
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

  ##
  # Whether this specification is stubbed - i.e. we have information
  # about the gem from a stub line, without having to evaluate the
  # entire gemspec file.
  def stubbed?
    raise NotImplementedError
  end

end

