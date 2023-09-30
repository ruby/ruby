# frozen_string_literal: true

##
#
# Gem::PathSupport facilitates the GEM_HOME and GEM_PATH environment settings
# to the rest of RubyGems.
#
class Gem::PathSupport
  ##
  # The default system path for managing Gems.
  attr_reader :home

  ##
  # Array of paths to search for Gems.
  attr_reader :path

  ##
  # Directory with spec cache
  attr_reader :spec_cache_dir # :nodoc:

  ##
  # Whether `Gem.paths.home` defaulted to a user install or not.
  attr_reader :auto_user_install

  ##
  #
  # Constructor. Takes a single argument which is to be treated like a
  # hashtable, or defaults to ENV, the system environment.
  #
  def initialize(env)
    # Current implementation of @home, which is exposed as `Gem.paths.home`:
    # 1. If `env["GEM_HOME"]` is defined in the environment: `env["GEM_HOME"]`.
    # 2. If `Gem.default_dir` is writable OR it does not exist and it's parent
    #    directory is writable: `Gem.default_dir`.
    # 3. Otherwise: `Gem.user_dir`.

    if env.key?("GEM_HOME")
      @home = normalize_home_dir(env["GEM_HOME"])
    elsif File.writable?(Gem.default_dir) || \
          (!File.exist?(Gem.default_dir) && File.writable?(File.expand_path("..", Gem.default_dir)))

      @home = normalize_home_dir(Gem.default_dir)
    else
      # If `GEM_HOME` is not set AND we can't use `Gem.default_dir`,
      # default to a user installation and set `@auto_user_install`.
      @auto_user_install = true
      @home = normalize_home_dir(Gem.user_dir)
    end

    @path = split_gem_path env["GEM_PATH"], @home

    @spec_cache_dir = env["GEM_SPEC_CACHE"] || Gem.default_spec_cache_dir

    @spec_cache_dir = @spec_cache_dir.dup.tap(&Gem::UNTAINT)
  end

  private

  def normalize_home_dir(home)
    if File::ALT_SEPARATOR
      home = home.gsub(File::ALT_SEPARATOR, File::SEPARATOR)
    end

    expand(home)
  end

  ##
  # Split the Gem search path (as reported by Gem.path).

  def split_gem_path(gpaths, home)
    # FIX: it should be [home, *path], not [*path, home]

    gem_path = []

    if gpaths
      gem_path = gpaths.split(Gem.path_separator)
      # Handle the path_separator being set to a regexp, which will cause
      # end_with? to error
      if /#{Gem.path_separator}\z/.match?(gpaths)
        gem_path += default_path
      end

      if File::ALT_SEPARATOR
        gem_path.map! do |this_path|
          this_path.gsub File::ALT_SEPARATOR, File::SEPARATOR
        end
      end

      gem_path << home
    else
      gem_path = default_path
    end

    gem_path.map {|path| expand(path) }.uniq
  end

  # Return the default Gem path
  def default_path
    Gem.default_path + [@home]
  end

  def expand(path)
    if File.directory?(path)
      File.realpath(path)
    else
      path
    end
  end
end
