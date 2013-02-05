#--
# This file contains all the various exceptions and other errors that are used
# inside of RubyGems.
#
# DOC: Confirm _all_
#++

module Gem
  ##
  # Raised when RubyGems is unable to load or activate a gem.  Contains the
  # name and version requirements of the gem that either conflicts with
  # already activated gems or that RubyGems is otherwise unable to activate.

  class LoadError < ::LoadError
    # Name of gem
    attr_accessor :name

    # Version requirement of gem
    attr_accessor :requirement
  end

  # FIX: does this need to exist? The subclass is the only other reference
  # I can find.
  class ErrorReason; end

  # Generated when trying to lookup a gem to indicate that the gem
  # was found, but that it isn't usable on the current platform.
  #
  # fetch and install read these and report them to the user to aid
  # in figuring out why a gem couldn't be installed.
  #
  class PlatformMismatch < ErrorReason

    ##
    # the name of the gem
    attr_reader :name

    ##
    # the version
    attr_reader :version

    ##
    # The platforms that are mismatched
    attr_reader :platforms

    def initialize(name, version)
      @name = name
      @version = version
      @platforms = []
    end

    ##
    # append a platform to the list of mismatched platforms.
    #
    # Platforms are added via this instead of injected via the constructor
    # so that we can loop over a list of mismatches and just add them rather
    # than perform some kind of calculation mismatch summary before creation.
    def add_platform(platform)
      @platforms << platform
    end

    ##
    # A wordy description of the error.
    def wordy
      "Found %s (%), but was for platform%s %s" %
        [@name,
         @version,
         @platforms.size == 1 ? 's' : '',
         @platforms.join(' ,')]
    end
  end

  ##
  # An error that indicates we weren't able to fetch some
  # data from a source

  class SourceFetchProblem < ErrorReason
    def initialize(source, error)
      @source = source
      @error = error
    end

    attr_reader :source, :error

    def wordy
      "Unable to download data from #{@source.uri} - #{@error.message}"
    end
  end
end
