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
    @extensions      = nil
    @name            = nil
    @spec            = nil
  end

  ##
  # True when this gem has been activated

  def activated?
    @activated ||=
    begin
      loaded = Gem.loaded_specs[name]
      loaded && loaded.version == version
    end
  end

  def build_extensions # :nodoc:
    return if default_gem?
    return if extensions.empty?

    to_spec.build_extensions
  end

  ##
  # If the gemspec contains a stubline, returns a StubLine instance. Otherwise
  # returns the full Gem::Specification.

  def data
    unless @data
      @extensions = []

      open loaded_from, OPEN_MODE do |file|
        begin
          file.readline # discard encoding line
          stubline = file.readline.chomp
          if stubline.start_with?(PREFIX) then
            @data = StubLine.new stubline

            @extensions = $'.split "\0" if
              /\A#{PREFIX}/ =~ file.readline.chomp
          end
        rescue EOFError
        end
      end
    end

    @data ||= to_spec
  end

  private :data

  ##
  # Extensions for this gem

  def extensions
    return @extensions if @extensions

    data # load

    @extensions
  end

  ##
  # If a gem has a stub specification it doesn't need to bother with
  # compatibility with original_name gems.  It was installed with the
  # normalized name.

  def find_full_gem_path # :nodoc:
    path = File.expand_path File.join gems_dir, full_name
    path.untaint
    path
  end

  ##
  # Full paths in the gem to add to <code>$LOAD_PATH</code> when this gem is
  # activated.

  def full_require_paths
    @require_paths ||= data.require_paths

    super
  end

  def missing_extensions?
    return false if default_gem?
    return false if extensions.empty?

    to_spec.missing_extensions?
  end

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

    super
  end

  ##
  # The full Gem::Specification for this gem, loaded from evalling its gemspec

  def to_spec
    @spec ||= if @data then
                Gem.loaded_specs.values.find { |spec|
                  spec.name == name and spec.version == version
                }
              end

    @spec ||= Gem::Specification.load(loaded_from)
    @spec.ignored = @ignored if instance_variable_defined? :@ignored

    @spec
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

  ##
  # Is there a stub line present for this StubSpecification?

  def stubbed?
    data.is_a? StubLine
  end

end

