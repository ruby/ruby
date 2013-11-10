# TODO: the documentation in here is terrible.
#
# Each exception needs a brief description and the scenarios where it is
# likely to be raised

##
# Base exception class for RubyGems.  All exception raised by RubyGems are a
# subclass of this one.
class Gem::Exception < RuntimeError

  ##
  #--
  # TODO: remove in RubyGems 3, nobody sets this

  attr_accessor :source_exception # :nodoc:

end

class Gem::CommandLineError < Gem::Exception; end

class Gem::DependencyError < Gem::Exception; end

class Gem::DependencyRemovalException < Gem::Exception; end

##
# Raised by Gem::DependencyResolver when a Gem::DependencyConflict reaches the
# toplevel.  Indicates which dependencies were incompatible through #conflict
# and #conflicting_dependencies

class Gem::DependencyResolutionError < Gem::Exception

  attr_reader :conflict

  def initialize conflict
    @conflict = conflict
    a, b = conflicting_dependencies

    super "conflicting dependencies #{a} and #{b}\n#{@conflict.explanation}"
  end

  def conflicting_dependencies
    @conflict.conflicting_dependencies
  end

end

##
# Raised when attempting to uninstall a gem that isn't in GEM_HOME.

class Gem::GemNotInHomeException < Gem::Exception
  attr_accessor :spec
end

class Gem::DocumentError < Gem::Exception; end

##
# Potentially raised when a specification is validated.
class Gem::EndOfYAMLException < Gem::Exception; end

##
# Signals that a file permission error is preventing the user from
# operating on the given directory.

class Gem::FilePermissionError < Gem::Exception

  attr_reader :directory

  def initialize directory
    @directory = directory

    super "You don't have write permissions for the #{directory} directory."
  end

end

##
# Used to raise parsing and loading errors
class Gem::FormatException < Gem::Exception
  attr_accessor :file_path
end

class Gem::GemNotFoundException < Gem::Exception; end

##
# Raised by the DependencyInstaller when a specific gem cannot be found

class Gem::SpecificGemNotFoundException < Gem::GemNotFoundException

  ##
  # Creates a new SpecificGemNotFoundException for a gem with the given +name+
  # and +version+.  Any +errors+ encountered when attempting to find the gem
  # are also stored.

  def initialize(name, version, errors=nil)
    super "Could not find a valid gem '#{name}' (#{version}) locally or in a repository"

    @name = name
    @version = version
    @errors = errors
  end

  ##
  # The name of the gem that could not be found.

  attr_reader :name

  ##
  # The version of the gem that could not be found.

  attr_reader :version

  ##
  # Errors encountered attempting to find the gem.

  attr_reader :errors

end

##
# Raised by Gem::DependencyResolver when dependencies conflict and create the
# inability to find a valid possible spec for a request.

class Gem::ImpossibleDependenciesError < Gem::Exception

  attr_reader :conflicts
  attr_reader :request

  def initialize request, conflicts
    @request   = request
    @conflicts = conflicts

    super build_message
  end

  def build_message # :nodoc:
    requester  = @request.requester
    requester  = requester ? requester.spec.full_name : 'The user'
    dependency = @request.dependency

    message = "#{requester} requires #{dependency} but it conflicted:\n"

    @conflicts.each do |_, conflict|
      message << conflict.explanation
    end

    message
  end

  def dependency
    @request.dependency
  end

end

class Gem::InstallError < Gem::Exception; end

##
# Potentially raised when a specification is validated.
class Gem::InvalidSpecificationException < Gem::Exception; end

class Gem::OperationNotSupportedError < Gem::Exception; end

##
# Signals that a remote operation cannot be conducted, probably due to not
# being connected (or just not finding host).
#--
# TODO: create a method that tests connection to the preferred gems server.
# All code dealing with remote operations will want this.  Failure in that
# method should raise this error.
class Gem::RemoteError < Gem::Exception; end

class Gem::RemoteInstallationCancelled < Gem::Exception; end

class Gem::RemoteInstallationSkipped < Gem::Exception; end

##
# Represents an error communicating via HTTP.
class Gem::RemoteSourceException < Gem::Exception; end

##
# Raised when a gem dependencies file specifies a ruby version that does not
# match the current version.

class Gem::RubyVersionMismatch < Gem::Exception; end

##
# Raised by Gem::Validator when something is not right in a gem.

class Gem::VerificationError < Gem::Exception; end

##
# Raised to indicate that a system exit should occur with the specified
# exit_code

class Gem::SystemExitException < SystemExit

  ##
  # The exit code for the process

  attr_accessor :exit_code

  ##
  # Creates a new SystemExitException with the given +exit_code+

  def initialize(exit_code)
    @exit_code = exit_code

    super "Exiting RubyGems with exit_code #{exit_code}"
  end

end

##
# Raised by DependencyResolver when a dependency requests a gem for which
# there is no spec.

class Gem::UnsatisfiableDependencyError < Gem::Exception

  ##
  # The unsatisfiable dependency.  This is a
  # Gem::DependencyResolver::DependencyRequest, not a Gem::Dependency

  attr_reader :dependency

  ##
  # Creates a new UnsatisfiableDepedencyError for the unsatisfiable
  # Gem::DependencyResolver::DependencyRequest +dep+

  def initialize dep, platform_mismatch=nil
    if platform_mismatch and !platform_mismatch.empty?
      plats = platform_mismatch.map { |x| x.platform.to_s }.sort.uniq
      super "Unable to resolve dependency: No match for '#{dep}' on this platform. Found: #{plats.join(', ')}"
    else
      if dep.explicit?
        super "Unable to resolve dependency: user requested '#{dep}'"
      else
        super "Unable to resolve dependency: '#{dep.request_context}' requires '#{dep}'"
      end
    end

    @dependency = dep
  end

end

##
# Backwards compatible typo'd exception class for early RubyGems 2.0.x

Gem::UnsatisfiableDepedencyError = Gem::UnsatisfiableDependencyError # :nodoc:

