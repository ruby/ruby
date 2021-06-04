require 'mspec/utils/deprecate'
require 'mspec/utils/version'
require 'mspec/guards/guard'

class VersionGuard < SpecGuard
  FULL_RUBY_VERSION = SpecVersion.new SpecGuard.ruby_version(:full)

  def initialize(version, requirement)
    version = SpecVersion.new(version) unless SpecVersion === version
    @version = version

    case requirement
    when String
      @requirement = SpecVersion.new requirement
    when Range
      MSpec.deprecate "an empty version range end", 'a specific version' if requirement.end.empty?
      a = SpecVersion.new requirement.begin
      b = SpecVersion.new requirement.end
      unless requirement.exclude_end?
        MSpec.deprecate "ruby_version_is with an inclusive range", 'an exclusive range ("2.1"..."2.3")'
      end
      @requirement = requirement.exclude_end? ? a...b : a..b
    else
      raise "version must be a String or Range but was a #{requirement.class}"
    end
    super(@version, @requirement)
  end

  def match?
    if Range === @requirement
      @requirement.include? @version
    else
      @version >= @requirement
    end
  end
end

def version_is(base_version, requirement, &block)
  VersionGuard.new(base_version, requirement).run_if(:version_is, &block)
end

def ruby_version_is(requirement, &block)
  VersionGuard.new(VersionGuard::FULL_RUBY_VERSION, requirement).run_if(:ruby_version_is, &block)
end
