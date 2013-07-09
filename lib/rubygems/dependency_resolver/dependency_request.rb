##
# Used Internally. Wraps a Dependency object to also track which spec
# contained the Dependency.

class Gem::DependencyResolver::DependencyRequest

  attr_reader :dependency

  attr_reader :requester

  def initialize(dep, act)
    @dependency = dep
    @requester = act
  end

  def ==(other)
    case other
    when Gem::Dependency
      @dependency == other
    when Gem::DependencyResolver::DependencyRequest
      @dependency == other.dependency && @requester == other.requester
    else
      false
    end
  end

  def matches_spec?(spec)
    @dependency.matches_spec? spec
  end

  def name
    @dependency.name
  end

  def pretty_print q # :nodoc:
    q.group 2, '[Dependency request ', ']' do
      q.breakable
      q.text @dependency.to_s

      q.breakable
      q.text ' requested by '
      q.pp @requester
    end
  end

  def to_s # :nodoc:
    @dependency.to_s
  end

end

