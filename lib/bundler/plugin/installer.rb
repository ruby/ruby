# frozen_string_literal: true

module Bundler
  # Handles the installation of plugin in appropriate directories.
  #
  # This class is supposed to be wrapper over the existing gem installation infra
  # but currently it itself handles everything as the Source's subclasses (e.g. Source::RubyGems)
  # are heavily dependent on the Gemfile.
  module Plugin
    class Installer
      autoload :Rubygems, "bundler/plugin/installer/rubygems"
      autoload :Git,      "bundler/plugin/installer/git"

      def install(names, options)
        version = options[:version] || [">= 0"]
        Bundler.settings.temporary(:lockfile_uses_separate_rubygems_sources => false, :disable_multisource => false) do
          if options[:git]
            install_git(names, version, options)
          else
            sources = options[:source] || Bundler.rubygems.sources
            install_rubygems(names, version, sources)
          end
        end
      end

      # Installs the plugin from Definition object created by limited parsing of
      # Gemfile searching for plugins to be installed
      #
      # @param [Definition] definition object
      # @return [Hash] map of names to their specs they are installed with
      def install_definition(definition)
        def definition.lock(*); end
        definition.resolve_remotely!
        specs = definition.specs

        install_from_specs specs
      end

    private

      def install_git(names, version, options)
        uri = options.delete(:git)
        options["uri"] = uri

        source_list = SourceList.new
        source_list.add_git_source(options)

        # To support both sources
        if options[:source]
          source_list.add_rubygems_source("remotes" => options[:source])
        end

        deps = names.map {|name| Dependency.new name, version }

        definition = Definition.new(nil, deps, source_list, true)
        install_definition(definition)
      end

      # Installs the plugin from rubygems source and returns the path where the
      # plugin was installed
      #
      # @param [String] name of the plugin gem to search in the source
      # @param [Array] version of the gem to install
      # @param [String, Array<String>] source(s) to resolve the gem
      #
      # @return [Hash] map of names to the specs of plugins installed
      def install_rubygems(names, version, sources)
        deps = names.map {|name| Dependency.new name, version }

        source_list = SourceList.new
        source_list.add_rubygems_source("remotes" => sources)

        definition = Definition.new(nil, deps, source_list, true)
        install_definition(definition)
      end

      # Installs the plugins and deps from the provided specs and returns map of
      # gems to their paths
      #
      # @param specs to install
      #
      # @return [Hash] map of names to the specs
      def install_from_specs(specs)
        paths = {}

        specs.each do |spec|
          spec.source.install spec

          paths[spec.name] = spec
        end

        paths
      end
    end
  end
end
