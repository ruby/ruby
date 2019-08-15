# frozen_string_literal: true

module Bundler
  # used for Creating Specifications from the Gemcutter Endpoint
  class EndpointSpecification < Gem::Specification
    ILLFORMED_MESSAGE = 'Ill-formed requirement ["#<YAML::Syck::DefaultKey'.freeze
    include MatchPlatform

    attr_reader :name, :version, :platform, :required_rubygems_version, :required_ruby_version, :checksum
    attr_accessor :source, :remote, :dependencies

    def initialize(name, version, platform, dependencies, metadata = nil)
      super()
      @name         = name
      @version      = Gem::Version.create version
      @platform     = platform
      @dependencies = dependencies.map {|dep, reqs| build_dependency(dep, reqs) }

      @loaded_from          = nil
      @remote_specification = nil

      parse_metadata(metadata)
    end

    def fetch_platform
      @platform
    end

    # needed for standalone, load required_paths from local gemspec
    # after the gem is installed
    def require_paths
      if @remote_specification
        @remote_specification.require_paths
      elsif _local_specification
        _local_specification.require_paths
      else
        super
      end
    end

    # needed for inline
    def load_paths
      # remote specs aren't installed, and can't have load_paths
      if _local_specification
        _local_specification.load_paths
      else
        super
      end
    end

    # needed for binstubs
    def executables
      if @remote_specification
        @remote_specification.executables
      elsif _local_specification
        _local_specification.executables
      else
        super
      end
    end

    # needed for bundle clean
    def bindir
      if @remote_specification
        @remote_specification.bindir
      elsif _local_specification
        _local_specification.bindir
      else
        super
      end
    end

    # needed for post_install_messages during install
    def post_install_message
      if @remote_specification
        @remote_specification.post_install_message
      elsif _local_specification
        _local_specification.post_install_message
      else
        super
      end
    end

    # needed for "with native extensions" during install
    def extensions
      if @remote_specification
        @remote_specification.extensions
      elsif _local_specification
        _local_specification.extensions
      else
        super
      end
    end

    def _local_specification
      return unless @loaded_from && File.exist?(local_specification_path)
      eval(File.read(local_specification_path)).tap do |spec|
        spec.loaded_from = @loaded_from
      end
    end

    def __swap__(spec)
      SharedHelpers.ensure_same_dependencies(self, dependencies, spec.dependencies)
      @remote_specification = spec
    end

  private

    def local_specification_path
      "#{base_dir}/specifications/#{full_name}.gemspec"
    end

    def parse_metadata(data)
      return unless data
      data.each do |k, v|
        next unless v
        case k.to_s
        when "checksum"
          @checksum = v.last
        when "rubygems"
          @required_rubygems_version = Gem::Requirement.new(v)
        when "ruby"
          @required_ruby_version = Gem::Requirement.new(v)
        end
      end
    rescue StandardError => e
      raise GemspecError, "There was an error parsing the metadata for the gem #{name} (#{version}): #{e.class}\n#{e}\nThe metadata was #{data.inspect}"
    end

    def build_dependency(name, requirements)
      Gem::Dependency.new(name, requirements)
    rescue ArgumentError => e
      raise unless e.message.include?(ILLFORMED_MESSAGE)
      puts # we shouldn't print the error message on the "fetching info" status line
      raise GemspecError,
        "Unfortunately, the gem #{name} (#{version}) has an invalid " \
        "gemspec.\nPlease ask the gem author to yank the bad version to fix " \
        "this issue. For more information, see http://bit.ly/syck-defaultkey."
    end
  end
end
