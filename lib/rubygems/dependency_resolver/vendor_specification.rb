class Gem::DependencyResolver::VendorSpecification

  attr_reader :spec

  attr_reader :set

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
    @source ||= Gem::Source::Vendor.new
  end

  def version
    @spec.version
  end

end

