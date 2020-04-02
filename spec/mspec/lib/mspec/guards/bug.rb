require 'mspec/guards/version'

class BugGuard < VersionGuard
  def initialize(bug, requirement)
    @bug = bug
    if String === requirement
      MSpec.deprecate "ruby_bug with a single version", 'an exclusive range ("2.1"..."2.3")'
      super(FULL_RUBY_VERSION, requirement)
      @requirement = SpecVersion.new requirement, true
    else
      super(FULL_RUBY_VERSION, requirement)
    end
  end

  def match?
    return false if MSpec.mode? :no_ruby_bug
    return false unless PlatformGuard.standard?

    if Range === @requirement
      super
    else
      FULL_RUBY_VERSION <= @requirement
    end
  end
end

def ruby_bug(bug, requirement, &block)
  BugGuard.new(bug, requirement).run_unless(:ruby_bug, &block)
end
