##
# Gem::StubSpecification reads the stub: line from the gemspec.  This prevents
# us having to eval the entire gemspec in order to find out certain
# information.

class Gem::StubSpecification < Gem::BasicSpecification
  # :nodoc:
  PREFIX = "# stub: "

  OPEN_MODE = # :nodoc:
    if Object.const_defined? :Encoding then
      'r:UTF-8:-'
    else
      'r'
    end

  class StubLine # :nodoc: all
    attr_reader :parts

    def initialize(data)
      @parts = data[PREFIX.length..-1].split(" ")
    end

    def name
      @parts[0]
    end

    def version
      Gem::Version.new @parts[1]
    end

    def platform
      Gem::Platform.new @parts[2]
    end

    def require_paths
      @parts[3..-1].join(" ").split("\0")
    end
  end

  def initialize(filename)
    self.loaded_from = filename
    @data            = nil
    @spec            = nil
  end

  ##
  # True when this gem has been activated

  def activated?
    loaded = Gem.loaded_specs[name]
    loaded && loaded.version == version
  end

  ##
  # If the gemspec contains a stubline, returns a StubLine instance. Otherwise
  # returns the full Gem::Specification.

  def data
    unless @data
      open loaded_from, OPEN_MODE do |file|
        begin
          file.readline # discard encoding line
          stubline = file.readline.chomp
          @data = StubLine.new(stubline) if stubline.start_with?(PREFIX)
        rescue EOFError
        end
      end
    end

    @data ||= to_spec
  end

  private :data

  ##
  # Name of the gem

  def name
    @name ||= data.name
  end

  ##
  # Platform of the gem

  def platform
    @platform ||= data.platform
  end

  ##
  # Require paths of the gem

  def require_paths
    @require_paths ||= data.require_paths
  end

  ##
  # The full Gem::Specification for this gem, loaded from evalling its gemspec

  def to_spec
    @spec ||= Gem::Specification.load(loaded_from)
  end

  ##
  # Is this StubSpecification valid? i.e. have we found a stub line, OR does
  # the filename contain a valid gemspec?

  def valid?
    data
  end

  ##
  # Version of the gem

  def version
    @version ||= data.version
  end

end

