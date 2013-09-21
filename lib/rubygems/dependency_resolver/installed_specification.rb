class Gem::DependencyResolver::InstalledSpecification

  attr_reader :spec

  def initialize set, spec, source=nil
    @set    = set
    @source = source
    @spec   = spec
  end

  def == other # :nodoc:
    self.class === other and
      @set  == other.set and
      @spec == other.spec
  end

  def dependencies
    @spec.dependencies
  end

  def full_name
    "#{@spec.name}-#{@spec.version}"
  end

  def name
    @spec.name
  end

  def platform
    @spec.platform
  end

  def source
    @source ||= Gem::Source::Installed.new
  end

  def version
    @spec.version
  end

end

