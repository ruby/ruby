require 'digest'
require 'rubygems/util'

##
# A git gem for use in a gem dependencies file.
#
# Example:
#
#   source =
#     Gem::Source::Git.new 'rake', 'git@example:rake.git', 'rake-10.1.0', false
#
#   source.specs

class Gem::Source::Git < Gem::Source

  ##
  # The name of the gem created by this git gem.

  attr_reader :name

  ##
  # The commit reference used for checking out this git gem.

  attr_reader :reference

  ##
  # The git repository this gem is sourced from.

  attr_reader :repository

  ##
  # The directory for cache and git gem installation

  attr_accessor :root_dir

  ##
  # Does this repository need submodules checked out too?

  attr_reader :need_submodules

  ##
  # Creates a new git gem source for a gems from loaded from +repository+ at
  # the given +reference+.  The +name+ is only used to track the repository
  # back to a gem dependencies file, it has no real significance as a git
  # repository may contain multiple gems.  If +submodules+ is true, submodules
  # will be checked out when the gem is installed.

  def initialize name, repository, reference, submodules = false
    super(nil)

    @name            = name
    @repository      = repository
    @reference       = reference
    @need_submodules = submodules

    @root_dir = Gem.dir
    @git      = ENV['git'] || 'git'
  end

  def <=> other
    case other
    when Gem::Source::Git then
      0
    when Gem::Source::Installed,
         Gem::Source::Lock then
      -1
    when Gem::Source then
      1
    else
      nil
    end
  end

  def == other # :nodoc:
    super and
      @name            == other.name and
      @repository      == other.repository and
      @reference       == other.reference and
      @need_submodules == other.need_submodules
  end

  ##
  # Checks out the files for the repository into the install_dir.

  def checkout # :nodoc:
    cache

    unless File.exist? install_dir then
      system @git, 'clone', '--quiet', '--no-checkout',
             repo_cache_dir, install_dir
    end

    Dir.chdir install_dir do
      system @git, 'fetch', '--quiet', '--force', '--tags', install_dir

      success = system @git, 'reset', '--quiet', '--hard', @reference

      success &&=
        Gem::Util.silent_system @git, 'submodule', 'update',
               '--quiet', '--init', '--recursive' if @need_submodules

      success
    end
  end

  ##
  # Creates a local cache repository for the git gem.

  def cache # :nodoc:
    if File.exist? repo_cache_dir then
      Dir.chdir repo_cache_dir do
        system @git, 'fetch', '--quiet', '--force', '--tags',
               @repository, 'refs/heads/*:refs/heads/*'
      end
    else
      system @git, 'clone', '--quiet', '--bare', '--no-hardlinks',
             @repository, repo_cache_dir
    end
  end

  ##
  # Directory where git gems get unpacked and so-forth.

  def base_dir # :nodoc:
    File.join @root_dir, 'bundler'
  end

  ##
  # A short reference for use in git gem directories

  def dir_shortref # :nodoc:
    rev_parse[0..11]
  end

  ##
  # Nothing to download for git gems

  def download full_spec, path # :nodoc:
  end

  ##
  # The directory where the git gem will be installed.

  def install_dir # :nodoc:
    File.join base_dir, 'gems', "#{@name}-#{dir_shortref}"
  end

  def pretty_print q # :nodoc:
    q.group 2, '[Git: ', ']' do
      q.breakable
      q.text @repository

      q.breakable
      q.text @reference
    end
  end

  ##
  # The directory where the git gem's repository will be cached.

  def repo_cache_dir # :nodoc:
    File.join @root_dir, 'cache', 'bundler', 'git', "#{@name}-#{uri_hash}"
  end

  ##
  # Converts the git reference for the repository into a commit hash.

  def rev_parse # :nodoc:
    Dir.chdir repo_cache_dir do
      Gem::Util.popen(@git, 'rev-parse', @reference).strip
    end
  end

  ##
  # Loads all gemspecs in the repository

  def specs
    checkout

    Dir.chdir install_dir do
      Dir['{,*,*/*}.gemspec'].map do |spec_file|
        directory = File.dirname spec_file
        file      = File.basename spec_file

        Dir.chdir directory do
          spec = Gem::Specification.load file
          if spec then
            spec.base_dir = base_dir

            spec.extension_dir =
              File.join base_dir, 'extensions', Gem::Platform.local.to_s,
                Gem.extension_api_version, "#{name}-#{dir_shortref}"

            spec.full_gem_path = File.dirname spec.loaded_from if spec
          end
          spec
        end
      end.compact
    end
  end

  ##
  # A hash for the git gem based on the git repository URI.

  def uri_hash # :nodoc:
    normalized =
      if @repository =~ %r%^\w+://(\w+@)?% then
        uri = URI(@repository).normalize.to_s.sub %r%/$%,''
        uri.sub(/\A(\w+)/) { $1.downcase }
      else
        @repository
      end

    Digest::SHA1.hexdigest normalized
  end

end

