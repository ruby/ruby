##
# The LockSpecification comes from a lockfile (Gem::RequestSet::Lockfile).
#
# A LockSpecification's dependency information is pre-filled from the
# lockfile.

class Gem::Resolver::LockSpecification < Gem::Resolver::Specification

  def initialize set, name, version, source, platform
    super()

    @name     = name
    @platform = platform
    @set      = set
    @source   = source
    @version  = version

    @dependencies = []
    @spec         = nil
  end

  ##
  # This is a null install as a locked specification is considered installed.
  # +options+ are ignored.

  def install options
    destination = options[:install_dir] || Gem.dir

    if File.exist? File.join(destination, 'specifications', spec.spec_name) then
      yield nil
      return
    end

    super
  end

  ##
  # Adds +dependency+ from the lockfile to this specification

  def add_dependency dependency # :nodoc:
    @dependencies << dependency
  end

  ##
  # A specification constructed from the lockfile is returned

  def spec
    @spec ||= Gem::Specification.new do |s|
      s.name     = @name
      s.version  = @version
      s.platform = @platform

      s.dependencies.concat @dependencies
    end
  end

end

