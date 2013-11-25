##
# A GitSpecification represents a gem that is sourced from a git repository
# and is being loaded through a gem dependencies file through the +git:+
# option.

class Gem::Resolver::GitSpecification < Gem::Resolver::SpecSpecification

  def == other # :nodoc:
    self.class === other and
      @set  == other.set and
      @spec == other.spec and
      @source == other.source
  end

  ##
  # Installing a git gem only involves building the extensions and generating
  # the executables.

  def install options
    require 'rubygems/installer'

    installer = Gem::Installer.new '', options
    installer.spec = spec

    yield installer if block_given?

    installer.run_pre_install_hooks
    installer.build_extensions
    installer.run_post_build_hooks
    installer.generate_bin
    installer.run_post_install_hooks
  end

end

