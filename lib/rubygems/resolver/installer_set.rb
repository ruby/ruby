# frozen_string_literal: true
##
# A set of gems for installation sourced from remote sources and local .gem
# files

class Gem::Resolver::InstallerSet < Gem::Resolver::Set
  ##
  # List of Gem::Specification objects that must always be installed.

  attr_reader :always_install # :nodoc:

  ##
  # Only install gems in the always_install list

  attr_accessor :ignore_dependencies # :nodoc:

  ##
  # Do not look in the installed set when finding specifications.  This is
  # used by the --install-dir option to `gem install`

  attr_accessor :ignore_installed # :nodoc:

  ##
  # The remote_set looks up remote gems for installation.

  attr_reader :remote_set # :nodoc:

  ##
  # Creates a new InstallerSet that will look for gems in +domain+.

  def initialize(domain)
    super()

    @domain = domain
    @remote = consider_remote?

    @f = Gem::SpecFetcher.fetcher

    @always_install      = []
    @ignore_dependencies = false
    @ignore_installed    = false
    @local               = {}
    @local_source        = Gem::Source::Local.new
    @remote_set          = Gem::Resolver::BestSet.new
    @specs               = {}
  end

  ##
  # Looks up the latest specification for +dependency+ and adds it to the
  # always_install list.

  def add_always_install(dependency)
    request = Gem::Resolver::DependencyRequest.new dependency, nil

    found = find_all request

    found.delete_if do |s|
      s.version.prerelease? and not s.local?
    end unless dependency.prerelease?

    found = found.select do |s|
      Gem::Source::SpecificFile === s.source or
        Gem::Platform::RUBY == s.platform or
        Gem::Platform.local === s.platform
    end

    if found.empty?
      exc = Gem::UnsatisfiableDependencyError.new request
      exc.errors = errors

      raise exc
    end

    newest = found.max_by do |s|
      [s.version, s.platform == Gem::Platform::RUBY ? -1 : 1]
    end

    @always_install << newest.spec
  end

  ##
  # Adds a local gem requested using +dep_name+ with the given +spec+ that can
  # be loaded and installed using the +source+.

  def add_local(dep_name, spec, source)
    @local[dep_name] = [spec, source]
  end

  ##
  # Should local gems should be considered?

  def consider_local? # :nodoc:
    @domain == :both or @domain == :local
  end

  ##
  # Should remote gems should be considered?

  def consider_remote? # :nodoc:
    @domain == :both or @domain == :remote
  end

  ##
  # Errors encountered while resolving gems

  def errors
    @errors + @remote_set.errors
  end

  ##
  # Returns an array of IndexSpecification objects matching DependencyRequest
  # +req+.

  def find_all(req)
    res = []

    dep = req.dependency

    return res if @ignore_dependencies and
              @always_install.none? {|spec| dep.match? spec }

    name = dep.name

    dep.matching_specs.each do |gemspec|
      next if @always_install.any? {|spec| spec.name == gemspec.name }

      res << Gem::Resolver::InstalledSpecification.new(self, gemspec)
    end unless @ignore_installed

    if consider_local?
      matching_local = @local.values.select do |spec, _|
        req.match? spec
      end.map do |spec, source|
        Gem::Resolver::LocalSpecification.new self, spec, source
      end

      res.concat matching_local

      begin
        if local_spec = @local_source.find_gem(name, dep.requirement)
          res << Gem::Resolver::IndexSpecification.new(
            self, local_spec.name, local_spec.version,
            @local_source, local_spec.platform)
        end
      rescue Gem::Package::FormatError
        # ignore
      end
    end

    res.delete_if do |spec|
      spec.version.prerelease? and not dep.prerelease?
    end

    res.concat @remote_set.find_all req if consider_remote?

    res
  end

  def prefetch(reqs)
    @remote_set.prefetch(reqs) if consider_remote?
  end

  def prerelease=(allow_prerelease)
    super

    @remote_set.prerelease = allow_prerelease
  end

  def inspect # :nodoc:
    always_install = @always_install.map {|s| s.full_name }

    '#<%s domain: %s specs: %p always install: %p>' % [
      self.class, @domain, @specs.keys, always_install,
    ]
  end

  ##
  # Called from IndexSpecification to get a true Specification
  # object.

  def load_spec(name, ver, platform, source) # :nodoc:
    key = "#{name}-#{ver}-#{platform}"

    @specs.fetch key do
      tuple = Gem::NameTuple.new name, ver, platform

      @specs[key] = source.fetch_spec tuple
    end
  end

  ##
  # Has a local gem for +dep_name+ been added to this set?

  def local?(dep_name) # :nodoc:
    spec, _ = @local[dep_name]

    spec
  end

  def pretty_print(q) # :nodoc:
    q.group 2, '[InstallerSet', ']' do
      q.breakable
      q.text "domain: #{@domain}"

      q.breakable
      q.text 'specs: '
      q.pp @specs.keys

      q.breakable
      q.text 'always install: '
      q.pp @always_install
    end
  end

  def remote=(remote) # :nodoc:
    case @domain
    when :local then
      @domain = :both if remote
    when :remote then
      @domain = nil unless remote
    when :both then
      @domain = :local unless remote
    end
  end
end
