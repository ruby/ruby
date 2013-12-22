##
# A Resolver::Specification contains a subset of the information
# contained in a Gem::Specification.  Only the information necessary for
# dependency resolution in the resolver is included.

class Gem::Resolver::Specification

  ##
  # The dependencies of the gem for this specification

  attr_reader :dependencies

  ##
  # The name of the gem for this specification

  attr_reader :name

  ##
  # The platform this gem works on.

  attr_reader :platform

  ##
  # The set this specification came from.

  attr_reader :set

  ##
  # The source for this specification

  attr_reader :source

  ##
  # The version of the gem for this specification.

  attr_reader :version

  ##
  # Sets default instance variables for the specification.

  def initialize
    @dependencies = nil
    @name         = nil
    @platform     = nil
    @set          = nil
    @source       = nil
    @version      = nil
  end

  ##
  # The name and version of the specification.
  #
  # Unlike Gem::Specification#full_name, the platform is not included.

  def full_name
    "#{@name}-#{@version}"
  end

  ##
  # Installs this specification using the Gem::Installer +options+.  The
  # install method yields a Gem::Installer instance, which indicates the
  # gem will be installed, or +nil+, which indicates the gem is already
  # installed.

  def install options
    require 'rubygems/installer'

    destination = options[:install_dir] || Gem.dir

    Gem.ensure_gem_subdirectories destination

    gem = source.download spec, destination

    installer = Gem::Installer.new gem, options

    yield installer if block_given?

    installer.install
  end

  ##
  # Returns true if this specification is installable on this platform.

  def installable_platform?
    Gem::Platform.match spec.platform
  end

end

