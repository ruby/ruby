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

  def pretty_print q # :nodoc:
    q.group 2, '[Local:', ']' do
      q.breakable
      q.text @path
    end
  end

  ##
  # Orders this source against +other+.
  #
  # If +other+ is a SpecificFile from a different gem name +nil+ is returned.
  #
  # If +other+ is a SpecificFile from the same gem name the versions are
  # compared using Gem::Version#<=>
  #
  # Otherwise Gem::Source#<=> is used.

  def <=> other
    case other
    when Gem::Source::SpecificFile then
      return nil if @spec.name != other.spec.name

      @spec.version <=> other.spec.version
    else
      super
    end
  end

end
