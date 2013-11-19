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
#   spec = source.load_spec 'rake'
#
#   source.checkout

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
  # Does this repository need submodules checked out too?

  attr_reader :need_submodules

  ##
  # Creates a new git gem source for a gem with the given +name+ that will be
  # loaded from +reference+ in +repository+.  If +submodules+ is true,
  # submodules will be checked out when the gem is installed.

  def initialize name, repository, reference, submodules = false
    super(nil)

    @name            = name
    @repository      = repository
    @reference       = reference
    @need_submodules = submodules

    @git = ENV['git'] || 'git'
  end

  def <=> other
    case other
    when Gem::Source::Git then
      0
    when Gem::Source::Installed then
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
        system @git, 'submodule', 'update',
               '--quiet', '--init', '--recursive', out: IO::NULL if @need_submodules

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
  # A short reference for use in git gem directories

  def dir_shortref # :nodoc:
    rev_parse[0..11]
  end

  ##
  # The directory where the git gem will be installed.

  def install_dir # :nodoc:
    File.join Gem.dir, 'bundler', 'gems', "#{@name}-#{dir_shortref}"
  end

  ##
  # Loads a Gem::Specification for +name+ from this git repository.

  def load_spec name
    cache

    gemspec_reference = "#{@reference}:#{name}.gemspec"

    Dir.chdir repo_cache_dir do
      source = Gem::Util.popen @git, 'show', gemspec_reference

      source.force_encoding Encoding::UTF_8 if Object.const_defined? :Encoding
      source.untaint

      begin
        spec = eval source, binding, gemspec_reference

        return spec if Gem::Specification === spec

        warn "git gem specification for #{@repository} #{gemspec_reference} is not a Gem::Specification (#{spec.class} instead)."
      rescue SignalException, SystemExit
        raise
      rescue SyntaxError, Exception
        warn "invalid git gem specification for #{@repository} #{gemspec_reference}"
      end
    end
  end

  ##
  # The directory where the git gem's repository will be cached.

  def repo_cache_dir # :nodoc:
    File.join Gem.dir, 'cache', 'bundler', 'git', "#{@name}-#{uri_hash}"
  end

  ##
  # Converts the git reference for the repository into a commit hash.

  def rev_parse # :nodoc:
    # HACK no safe equivalent of ` exists on 1.8.7
    Dir.chdir repo_cache_dir do
      Gem::Util.popen(@git, 'rev-parse', @reference).strip
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

