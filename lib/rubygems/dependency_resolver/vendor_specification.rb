##
# A VendorSpecification represents a gem that has been unpacked into a project
# and is being loaded through a gem dependencies file through the +path:+
# option.

class Gem::DependencyResolver::VendorSpecification < Gem::DependencyResolver::SpecSpecification

  def == other # :nodoc:
    self.class === other and
      @set  == other.set and
      @spec == other.spec and
      @source == other.source
  end

end

