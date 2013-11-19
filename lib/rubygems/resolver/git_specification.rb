##
# A GitSpecification represents a gem that is sourced from a git repository
# and is being loaded through a gem dependencies file through the +git:+
# option.

class Gem::Resolver::GitSpecification < Gem::Resolver::SpecSpecification

  def == other # :nodoc:
    self.class === other and
      @set  == other.set and
      @spec == other.spec and
      @source == other.source
  end

end

