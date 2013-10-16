##
# Represents a possible Specification object returned from IndexSet.  Used to
# delay needed to download full Specification objects when only the +name+
# and +version+ are needed.

class Gem::DependencyResolver::IndexSpecification

  attr_reader :name

  attr_reader :platform

  attr_reader :source

  attr_reader :version

  def initialize set, name, version, source, platform
    @set = set
    @name = name
    @version = version
    @source = source
    @platform = platform.to_s

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

      unless Gem::Platform::RUBY == @platform then
        q.breakable
        q.text @platform.to_s
      end

      q.breakable
      q.text 'source '
      q.pp @source
    end
  end

  def spec
    @spec ||= @set.load_spec(@name, @version, @platform, @source)
  end

end

