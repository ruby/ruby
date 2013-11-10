##
# Represents a specification retrieved via the rubygems.org API.
#
# This is used to avoid loading the full Specification object when all we need
# is the name, version, and dependencies.

class Gem::DependencyResolver::APISpecification < Gem::DependencyResolver::Specification

  ##
  # Creates an APISpecification for the given +set+ from the rubygems.org
  # +api_data+.
  #
  # See http://guides.rubygems.org/rubygems-org-api/#misc_methods for the
  # format of the +api_data+.

  def initialize(set, api_data)
    super()

    @set = set
    @name = api_data[:name]
    @version = Gem::Version.new api_data[:number]
    @platform = api_data[:platform]
    @dependencies = api_data[:dependencies].map do |name, ver|
      Gem::Dependency.new name, ver.split(/\s*,\s*/)
    end
  end

  def == other # :nodoc:
    self.class === other and
      @set          == other.set and
      @name         == other.name and
      @version      == other.version and
      @platform     == other.platform and
      @dependencies == other.dependencies
  end

end

