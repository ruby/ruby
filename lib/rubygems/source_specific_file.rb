class Gem::Source::SpecificFile < Gem::Source
  def initialize(file)
    @uri = nil
    @path = ::File.expand_path(file)

    @package = Gem::Package.new @path
    @spec = @package.spec
    @name = @spec.name_tuple
  end

  attr_reader :spec

  def load_specs(*a)
    [@name]
  end

  def fetch_spec(name)
    return @spec if name == @name
    raise Gem::Exception, "Unable to find '#{name}'"
    @spec
  end

  def download(spec, dir=nil)
    return @path if spec == @spec
    raise Gem::Exception, "Unable to download '#{spec.full_name}'"
  end

end
