##
# Specifies a Specification object that should be activated.
# Also contains a dependency that was used to introduce this
# activation.

class Gem::DependencyResolver::ActivationRequest

  attr_reader :request

  attr_reader :spec

  def initialize spec, req, others_possible = true
    @spec = spec
    @request = req
    @others_possible = others_possible
  end

  def == other
    case other
    when Gem::Specification
      @spec == other
    when Gem::DependencyResolver::ActivationRequest
      @spec == other.spec && @request == other.request
    else
      false
    end
  end

  def download path
    if @spec.respond_to? :source
      source = @spec.source
    else
      source = Gem.sources.first
    end

    Gem.ensure_gem_subdirectories path

    source.download full_spec, path
  end

  def full_name
    @spec.full_name
  end

  def full_spec
    Gem::Specification === @spec ? @spec : @spec.spec
  end

  def inspect # :nodoc:
    others_possible = nil
    others_possible = ' (others possible)' if @others_possible

    '#<%s for %p from %s%s>' % [
      self.class, @spec, @request, others_possible
    ]
  end

  ##
  # Indicates if the requested gem has already been installed.

  def installed?
    this_spec = full_spec

    Gem::Specification.any? do |s|
      s == this_spec
    end
  end

  def name
    @spec.name
  end

  ##
  # Indicate if this activation is one of a set of possible
  # requests for the same Dependency request.

  def others_possible?
    @others_possible
  end

  ##
  # Return the ActivationRequest that contained the dependency
  # that we were activated for.

  def parent
    @request.requester
  end

  def pretty_print q # :nodoc:
    q.group 2, '[Activation request', ']' do
      q.breakable
      q.pp @spec

      q.breakable
      q.text ' for '
      q.pp @request


      q.breakable
      q.text ' (other possible)' if @others_possible
    end
  end

  def version
    @spec.version
  end

end

