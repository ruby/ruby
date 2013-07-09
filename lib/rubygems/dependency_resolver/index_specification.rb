##
# Represents a possible Specification object returned
# from IndexSet. Used to delay needed to download full
# Specification objects when only the +name+ and +version+
# are needed.

class Gem::DependencyResolver::IndexSpecification

  attr_reader :name

  attr_reader :source

  attr_reader :version

  def initialize set, name, version, source, plat
    @set = set
    @name = name
    @version = version
    @source = source
    @platform = plat

    @spec = nil
  end

  def dependencies
    spec.dependencies
  end

  def full_name
    "#{@name}-#{@version}"
  end

  def inspect # :nodoc:
    '#<%s %s source %s>' % [self.class, full_name, @source]
  end

  def pretty_print q # :nodoc:
    q.group 2, '[Index specification', ']' do
      q.breakable
      q.text full_name

      q.breakable
      q.text ' source '
      q.pp @source
    end
  end

  def spec
    @spec ||= @set.load_spec(@name, @version, @source)
  end

end

