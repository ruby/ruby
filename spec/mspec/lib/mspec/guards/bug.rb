require 'mspec/guards/version'

class BugGuard < VersionGuard
  def initialize(bug, version)
    @bug = bug
    if String === version
      MSpec.deprecate "ruby_bug with a single version", 'an exclusive range ("2.1"..."2.3")'
      @version = SpecVersion.new version, true
    else
      super(version)
    end
    @parameters = [@bug, @version]
  end

  def match?
    return false if MSpec.mode? :no_ruby_bug
    return false unless PlatformGuard.standard?
    if Range === @version
      super
    else
      FULL_RUBY_VERSION <= @version
    end
  end
end

class Object
  def ruby_bug(bug, version, &block)
    BugGuard.new(bug, version).run_unless(:ruby_bug, &block)
  end
end
