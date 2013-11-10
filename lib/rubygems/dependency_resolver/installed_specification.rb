##
# An InstalledSpecification represents a gem that is already installed
# locally.

class Gem::DependencyResolver::InstalledSpecification < Gem::DependencyResolver::SpecSpecification

  def == other # :nodoc:
    self.class === other and
      @set  == other.set and
      @spec == other.spec
  end

  ##
  # Returns +true+ if this gem is installable for the current platform.

  def installable_platform?
    # BACKCOMPAT If the file is coming out of a specified file, then we
    # ignore the platform. This code can be removed in RG 3.0.
    if @source.kind_of? Gem::Source::SpecificFile
      return true
    else
      Gem::Platform.match @spec.platform
    end
  end

  ##
  # The source for this specification

  def source
    @source ||= Gem::Source::Installed.new
  end

end

