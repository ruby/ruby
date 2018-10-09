# frozen_string_literal: true

module Bundler
  class CLI::Add
    def initialize(options, gems)
      @gems = gems
      @options = options
      @options[:group] = @options[:group].split(",").map(&:strip) if !@options[:group].nil? && !@options[:group].empty?
    end

    def run
      raise InvalidOption, "You can not specify `--strict` and `--optimistic` at the same time." if @options[:strict] && @options[:optimistic]

      # raise error when no gems are specified
      raise InvalidOption, "Please specify gems to add." if @gems.empty?

      version = @options[:version].nil? ? nil : @options[:version].split(",").map(&:strip)

      unless version.nil?
        version.each do |v|
          raise InvalidOption, "Invalid gem requirement pattern '#{v}'" unless Gem::Requirement::PATTERN =~ v.to_s
        end
      end

      dependencies = @gems.map {|g| Bundler::Dependency.new(g, version, @options) }

      Injector.inject(dependencies,
        :conservative_versioning => @options[:version].nil?, # Perform conservative versioning only when version is not specified
        :optimistic => @options[:optimistic],
        :strict => @options[:strict])

      Installer.install(Bundler.root, Bundler.definition) unless @options["skip-install"]
    end
  end
end
