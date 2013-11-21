##
# A GitSet represents gems that are sourced from git repositories.
#
# This is used for gem dependency file support.
#
# Example:
#
#   set = Gem::Resolver::GitSet.new
#   set.add_git_gem 'rake', 'git://example/rake.git', tag: 'rake-10.1.0'

class Gem::Resolver::GitSet < Gem::Resolver::Set

  ##
  # Contains repositories needing submodules

  attr_reader :need_submodules # :nodoc:

  ##
  # A Hash containing git gem names for keys and a Hash of repository and
  # git commit reference as values.

  attr_reader :repositories # :nodoc:

  ##
  # A hash of gem names to Gem::Resolver::GitSpecifications

  attr_reader :specs # :nodoc:

  def initialize # :nodoc:
    @git             = ENV['git'] || 'git'
    @need_submodules = {}
    @repositories    = {}
    @specs           = {}
  end

  def add_git_gem name, repository, reference, submodules # :nodoc:
    @repositories[name] = [repository, reference]
    @need_submodules[repository] = submodules
  end

  ##
  # Finds all git gems matching +req+

  def find_all req
    prefetch nil

    specs.values.select do |spec|
      req.matches_spec? spec
    end
  end

  ##
  # Prefetches specifications from the git repositories in this set.

  def prefetch reqs
    return unless @specs.empty?

    @repositories.each do |name, (repository, reference)|
      source = Gem::Source::Git.new name, repository, reference

      source.specs.each do |spec|
        git_spec = Gem::Resolver::GitSpecification.new self, spec, source

        @specs[spec.name] = git_spec
      end
    end
  end

end

