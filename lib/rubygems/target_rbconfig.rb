# frozen_string_literal: true

require "rbconfig"

##
# A TargetConfig is a wrapper around an RbConfig object that provides a
# consistent interface for querying configuration for *deployment target
# platform*, where the gem being installed is intended to run on.
#
# The TargetConfig is typically created from the RbConfig of the running Ruby
# process, but can also be created from an RbConfig file on disk for cross-
# compiling gems.

class Gem::TargetRbConfig
  attr_reader :path

  def initialize(rbconfig, path)
    @rbconfig = rbconfig
    @path = path
  end

  ##
  # Creates a TargetRbConfig for the platform that RubyGems is running on.

  def self.for_running_ruby
    new(::RbConfig, nil)
  end

  ##
  # Creates a TargetRbConfig from the RbConfig file at the given path.
  # Typically used for cross-compiling gems.

  def self.from_path(rbconfig_path)
    namespace = Module.new do |m|
      # Load the rbconfig.rb file within a new anonymous module to avoid
      # conflicts with the rbconfig for the running platform.
      Kernel.load rbconfig_path, m
    end
    rbconfig = namespace.const_get(:RbConfig)

    new(rbconfig, rbconfig_path)
  end

  ##
  # Queries the configuration for the given key.

  def [](key)
    @rbconfig::CONFIG[key]
  end
end
