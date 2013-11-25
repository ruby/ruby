##
# Used internally to indicate that a dependency conflicted
# with a spec that would be activated.

class Gem::Resolver::Conflict

  ##
  # The specification that was activated prior to the conflict

  attr_reader :activated

  ##
  # The dependency that is in conflict with the activated gem.

  attr_reader :dependency

  attr_reader :failed_dep # :nodoc:

  ##
  # Creates a new resolver conflict when +dependency+ is in conflict with an
  # already +activated+ specification.

  def initialize(dependency, activated, failed_dep=dependency)
    @dependency = dependency
    @activated = activated
    @failed_dep = failed_dep
  end

  def == other # :nodoc:
    self.class === other and
      @dependency == other.dependency and
      @activated  == other.activated  and
      @failed_dep == other.failed_dep
  end

  ##
  # A string explanation of the conflict.

  def explain
    "<Conflict wanted: #{@failed_dep}, had: #{activated.spec.full_name}>"
  end

  ##
  # Return the 2 dependency objects that conflicted

  def conflicting_dependencies
    [@failed_dep.dependency, @activated.request.dependency]
  end

  ##
  # Explanation of the conflict used by exceptions to print useful messages

  def explanation
    activated   = @activated.spec.full_name
    requirement = @failed_dep.dependency.requirement

    "  Activated %s via:\n    %s\n  instead of (%s) via:\n    %s\n" % [
      activated,   request_path(@activated).join(', '),
      requirement, request_path(requester).join(', '),
    ]
  end

  ##
  # Returns true if the conflicting dependency's name matches +spec+.

  def for_spec?(spec)
    @dependency.name == spec.name
  end

  def pretty_print q # :nodoc:
    q.group 2, '[Dependency conflict: ', ']' do
      q.breakable

      q.text 'activated '
      q.pp @activated

      q.breakable
      q.text ' dependency '
      q.pp @dependency

      q.breakable
      if @dependency == @failed_dep then
        q.text ' failed'
      else
        q.text ' failed dependency '
        q.pp @failed_dep
      end
    end
  end

  ##
  # Path of activations from the +current+ list.

  def request_path current
    path = []

    while current do
      requirement = current.request.dependency.requirement
      path << "#{current.spec.full_name} (#{requirement})"

      current = current.parent
    end

    path = ['user request (gem command or Gemfile)'] if path.empty?

    path
  end

  ##
  # Return the Specification that listed the dependency

  def requester
    @failed_dep.requester
  end

end

##
# TODO: Remove in RubyGems 3

Gem::Resolver::DependencyConflict = Gem::Resolver::Conflict # :nodoc:

