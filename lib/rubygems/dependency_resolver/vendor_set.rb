##
# A VendorSet represents gems that have been unpacked into a specific
# directory that contains a gemspec.
#
# This is used for gem dependency file support.
#
# Example:
#
#   set = Gem::DependencyResolver::VendorSet.new
#
#   set.add_vendor_gem 'rake', 'vendor/rake'
#
# The directory vendor/rake must contain an unpacked rake gem along with a
# rake.gemspec (watching the given name).

class Gem::DependencyResolver::VendorSet < Gem::DependencyResolver::Set

  def initialize # :nodoc:
    @directories = {}
    @specs       = {}
  end

  ##
  # Adds a specification to the set with the given +name+ which has been
  # unpacked into the given +directory+.

  def add_vendor_gem name, directory # :nodoc:
    gemspec = File.join directory, "#{name}.gemspec"

    spec = Gem::Specification.load gemspec

    raise Gem::GemNotFoundException,
          "unable to find #{gemspec} for gem #{name}" unless spec

    key = "#{spec.name}-#{spec.version}-#{spec.platform}"

    @specs[key]        = spec
    @directories[spec] = directory
  end

  ##
  # Returns an Array of VendorSpecification objects matching the
  # DependencyRequest +req+.

  def find_all req
    @specs.values.select do |spec|
      req.matches_spec? spec
    end.map do |spec|
      source = Gem::Source::Vendor.new @directories[spec]
      Gem::DependencyResolver::VendorSpecification.new self, spec, source
    end
  end

  ##
  # Loads a spec with the given +name+, +version+ and +platform+.  Since the
  # +source+ is defined when the specification was added to index it is not
  # used.

  def load_spec name, version, platform, source # :nodoc:
    key = "#{name}-#{version}-#{platform}"

    @specs.fetch key
  end

end

