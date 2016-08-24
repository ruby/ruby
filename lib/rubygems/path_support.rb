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
  #
  # Constructor. Takes a single argument which is to be treated like a
  # hashtable, or defaults to ENV, the system environment.
  #
  def initialize(env=ENV)
    @env = env

    # note 'env' vs 'ENV'...
    @home     = env["GEM_HOME"] || ENV["GEM_HOME"] || Gem.default_dir

    if File::ALT_SEPARATOR then
      @home   = @home.gsub(File::ALT_SEPARATOR, File::SEPARATOR)
    end

    self.path = env["GEM_PATH"] || ENV["GEM_PATH"]

    @spec_cache_dir =
      env["GEM_SPEC_CACHE"] || ENV["GEM_SPEC_CACHE"] ||
        Gem.default_spec_cache_dir

    @spec_cache_dir = @spec_cache_dir.dup.untaint
  end

  private

  ##
  # Set the Gem search path (as reported by Gem.path).

  def path=(gpaths)
    # FIX: it should be [home, *path], not [*path, home]

    gem_path = []

    # FIX: I can't tell wtf this is doing.
    gpaths ||= (ENV['GEM_PATH'] || "").empty? ? nil : ENV["GEM_PATH"]

    if gpaths
      if gpaths.kind_of?(Array)
        gem_path = gpaths.dup
      else
        gem_path = gpaths.split(Gem.path_separator)
        if gpaths.end_with?(Gem.path_separator)
          gem_path += default_path
        end
      end

      if File::ALT_SEPARATOR then
        gem_path.map! do |this_path|
          this_path.gsub File::ALT_SEPARATOR, File::SEPARATOR
        end
      end

      gem_path << @home
    else
      gem_path = default_path
    end

    @path = gem_path.uniq
  end

  # Return the default Gem path
  def default_path
    gem_path = Gem.default_path + [@home]

    if defined?(APPLE_GEM_HOME)
      gem_path << APPLE_GEM_HOME
    end
    gem_path
  end
end
