##
# Used internally to indicate that a dependency conflicted
# with a spec that would be activated.

class Gem::DependencyResolver::DependencyConflict

  attr_reader :activated

  attr_reader :dependency

  def initialize(dependency, activated, failed_dep=dependency)
    @dependency = dependency
    @activated = activated
    @failed_dep = failed_dep
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

    "  Activated %s instead of (%s) via:\n    %s\n" % [
      activated, requirement, request_path.join(', ')
    ]
  end

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
  # Path of specifications that requested this dependency

  def request_path
    current = requester
    path    = []

    while current do
      path << current.spec.full_name

      current = current.request.requester
    end

    path
  end

  ##
  # Return the Specification that listed the dependency

  def requester
    @failed_dep.requester
  end

end

