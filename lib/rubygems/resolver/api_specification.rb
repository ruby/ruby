# frozen_string_literal: true

##
# Represents a specification retrieved via the Compact Index API.
#
# This is used to avoid loading the full Specification object when all we need
# is the name, version, and dependencies.

class Gem::Resolver::APISpecification < Gem::Resolver::Specification
  ##
  # We assume that all instances of this class are immutable;
  # so avoid duplicated generation for performance.
  @@cache = {}
  def self.new(set, api_data)
    cache_key = [set, api_data]
    cache = @@cache[cache_key]
    return cache if cache
    @@cache[cache_key] = super
  end

  ##
  # Creates an APISpecification for the given +set+ from the Compact Index API
  # +api_data+.
  #
  # See https://guides.rubygems.org/rubygems-org-compact-index-api for the
  # format of the +api_data+.

  def initialize(set, api_data)
    super()

    @set = set
    @name = api_data[:name]
    @version = Gem::Version.new(api_data[:number]).freeze
    @platform = Gem::Platform.new(api_data[:platform]).freeze
    @original_platform = api_data[:platform].freeze
    @dependencies = api_data[:dependencies].map do |name, ver|
      Gem::Dependency.new(name, ver.split(/\s*,\s*/)).freeze
    end.freeze
    @required_ruby_version = Gem::Requirement.new(api_data.dig(:requirements, :ruby)).freeze
    @required_rubygems_version = Gem::Requirement.new(api_data.dig(:requirements, :rubygems)).freeze
    @created_at = parse_created_at(api_data.dig(:requirements, :created_at))&.freeze
  end

  def ==(other) # :nodoc:
    self.class === other &&
      @set          == other.set &&
      @name         == other.name &&
      @version      == other.version &&
      @platform     == other.platform
  end

  def hash
    @set.hash ^ @name.hash ^ @version.hash ^ @platform.hash
  end

  def fetch_development_dependencies # :nodoc:
    spec = source.fetch_spec Gem::NameTuple.new @name, @version, @platform

    @dependencies = spec.dependencies
  end

  def installable_platform? # :nodoc:
    Gem::Platform.match_gem? @platform, @name
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[APISpecification", "]" do
      q.breakable
      q.text "name: #{name}"

      q.breakable
      q.text "version: #{version}"

      q.breakable
      q.text "platform: #{platform}"

      q.breakable
      q.text "dependencies:"
      q.breakable
      q.pp @dependencies

      q.breakable
      q.text "set uri: #{@set.dep_uri}"
    end
  end

  ##
  # A Gem::Specification stub built from the Compact Index data for this
  # specification. The compact index carries everything needed to
  # download and install the gem, so the Marshal gemspec is not fetched.
  # Development dependencies are not included; see
  # #fetch_development_dependencies.

  def spec # :nodoc:
    @spec ||= Gem::Specification.new do |s|
      s.name     = @name
      s.version  = @version
      s.platform = @platform
      s.original_platform = @original_platform
      s.required_ruby_version = @required_ruby_version
      s.required_rubygems_version = @required_rubygems_version

      @dependencies.each do |dependency|
        s.add_runtime_dependency dependency.name, *dependency.requirement.as_list
      end
    end
  end

  def source # :nodoc:
    @set.source
  end

  private

  def parse_created_at(value)
    value = value.first if value.is_a?(Array)
    return unless value.is_a?(String)

    require "time"
    begin
      Time.iso8601(value)
    rescue ArgumentError
      nil
    end
  end
end
