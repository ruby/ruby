require 'mspec/utils/deprecate'
require 'mspec/utils/version'
require 'mspec/guards/guard'

class VersionGuard < SpecGuard
  FULL_RUBY_VERSION = SpecVersion.new SpecGuard.ruby_version(:full)

  def initialize(version)
    case version
    when String
      @version = SpecVersion.new version
    when Range
      MSpec.deprecate "an empty version range end", 'a specific version' if version.end.empty?
      a = SpecVersion.new version.begin
      b = SpecVersion.new version.end
      unless version.exclude_end?
        MSpec.deprecate "ruby_version_is with an inclusive range", 'an exclusive range ("2.1"..."2.3")'
      end
      @version = version.exclude_end? ? a...b : a..b
    else
      raise "version must be a String or Range but was a #{version.class}"
    end
    @parameters = [version]
  end

  def match?
    if Range === @version
      @version.include? FULL_RUBY_VERSION
    else
      FULL_RUBY_VERSION >= @version
    end
  end
end

class Object
  def ruby_version_is(*args, &block)
    VersionGuard.new(*args).run_if(:ruby_version_is, &block)
  end
end
