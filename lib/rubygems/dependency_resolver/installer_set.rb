##
# A set of gems for installation sourced from remote sources and local .gem
# files

class Gem::DependencyResolver::InstallerSet < Gem::DependencyResolver::Set

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

  def initialize domain
    @domain = domain

    @f = Gem::SpecFetcher.fetcher

    @all = Hash.new { |h,k| h[k] = [] }
    @always_install      = []
    @ignore_dependencies = false
    @ignore_installed    = false
    @loaded_remote_specs = []
    @specs               = {}
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
  # Returns an array of IndexSpecification objects matching DependencyRequest
  # +req+.

  def find_all req
    res = []

    dep  = req.dependency

    return res if @ignore_dependencies and
              @always_install.none? { |spec| dep.matches_spec? spec }

    name = dep.name

    dep.matching_specs.each do |gemspec|
      next if @always_install.include? gemspec

      res << Gem::DependencyResolver::InstalledSpecification.new(self, gemspec)
    end unless @ignore_installed

    if consider_local? then
      local_source = Gem::Source::Local.new

      if spec = local_source.find_gem(name, dep.requirement) then
        res << Gem::DependencyResolver::IndexSpecification.new(
          self, spec.name, spec.version, local_source, spec.platform)
      end
    end

    if consider_remote? then
      load_remote_specs dep

      @all[name].each do |remote_source, n|
        if dep.match? n then
          res << Gem::DependencyResolver::IndexSpecification.new(
            self, n.name, n.version, remote_source, n.platform)
        end
      end
    end

    res
  end

  def inspect # :nodoc:
    always_install = @always_install.map { |s| s.full_name }

    '#<%s domain: %s specs: %p always install: %p>' % [
      self.class, @domain, @specs.keys, always_install,
    ]
  end

  ##
  # Loads remote prerelease specs if +dep+ is a prerelease dependency

  def load_remote_specs dep # :nodoc:
    types = [:released]
    types << :prerelease if dep.prerelease?

    types.each do |type|
      next if @loaded_remote_specs.include? type
      @loaded_remote_specs << type

      list, = @f.available_specs type

      list.each do |uri, specs|
        specs.each do |n|
          @all[n.name] << [uri, n]
        end
      end
    end
  end

  ##
  # Called from IndexSpecification to get a true Specification
  # object.

  def load_spec name, ver, platform, source # :nodoc:
    key = "#{name}-#{ver}-#{platform}"

    @specs.fetch key do
      tuple = Gem::NameTuple.new name, ver, platform

      @specs[key] = source.fetch_spec tuple
    end
  end

  def pretty_print q # :nodoc:
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

end

