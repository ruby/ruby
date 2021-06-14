# frozen_string_literal: true

module Bundler
  class SourceList
    attr_reader :path_sources,
      :git_sources,
      :plugin_sources,
      :global_path_source,
      :metadata_source

    def global_rubygems_source
      @global_rubygems_source ||= rubygems_aggregate_class.new("allow_local" => true)
    end

    def initialize
      @path_sources           = []
      @git_sources            = []
      @plugin_sources         = []
      @global_rubygems_source = nil
      @global_path_source     = nil
      @rubygems_sources       = []
      @metadata_source        = Source::Metadata.new

      @merged_gem_lockfile_sections = false
    end

    def merged_gem_lockfile_sections?
      @merged_gem_lockfile_sections
    end

    def merged_gem_lockfile_sections!
      @merged_gem_lockfile_sections = true
    end

    def no_aggregate_global_source?
      global_rubygems_source.remotes.size <= 1
    end

    def add_path_source(options = {})
      if options["gemspec"]
        add_source_to_list Source::Gemspec.new(options), path_sources
      else
        path_source = add_source_to_list Source::Path.new(options), path_sources
        @global_path_source ||= path_source if options["global"]
        path_source
      end
    end

    def add_git_source(options = {})
      add_source_to_list(Source::Git.new(options), git_sources).tap do |source|
        warn_on_git_protocol(source)
      end
    end

    def add_rubygems_source(options = {})
      add_source_to_list Source::Rubygems.new(options), @rubygems_sources
    end

    def add_plugin_source(source, options = {})
      add_source_to_list Plugin.source(source).new(options), @plugin_sources
    end

    def global_rubygems_source=(uri)
      @global_rubygems_source ||= rubygems_aggregate_class.new("remotes" => uri, "allow_local" => true)
    end

    def add_rubygems_remote(uri)
      global_rubygems_source.add_remote(uri)
      global_rubygems_source
    end

    def default_source
      global_path_source || global_rubygems_source
    end

    def rubygems_sources
      non_global_rubygems_sources + [global_rubygems_source]
    end

    def non_global_rubygems_sources
      @rubygems_sources
    end

    def rubygems_remotes
      rubygems_sources.map(&:remotes).flatten.uniq
    end

    def all_sources
      path_sources + git_sources + plugin_sources + rubygems_sources + [metadata_source]
    end

    def non_default_explicit_sources
      all_sources - [default_source, metadata_source]
    end

    def get(source)
      source_list_for(source).find {|s| equal_source?(source, s) || equivalent_source?(source, s) }
    end

    def lock_sources
      lock_other_sources + lock_rubygems_sources
    end

    def lock_other_sources
      (path_sources + git_sources + plugin_sources).sort_by(&:to_s)
    end

    def lock_rubygems_sources
      if merged_gem_lockfile_sections?
        [combine_rubygems_sources]
      else
        rubygems_sources.sort_by(&:to_s).uniq
      end
    end

    # Returns true if there are changes
    def replace_sources!(replacement_sources)
      return true if replacement_sources.empty?

      [path_sources, git_sources, plugin_sources].each do |source_list|
        source_list.map! do |source|
          replacement_sources.find {|s| s == source } || source
        end
      end

      replacement_rubygems = merged_gem_lockfile_sections? &&
        replacement_sources.detect {|s| s.is_a?(Source::Rubygems) }
      @global_rubygems_source = replacement_rubygems if replacement_rubygems

      return true if !equal_sources?(lock_sources, replacement_sources) && !equivalent_sources?(lock_sources, replacement_sources)

      false
    end

    def cached!
      all_sources.each(&:cached!)
    end

    def remote!
      all_sources.each(&:remote!)
    end

    private

    def rubygems_aggregate_class
      Source::Rubygems
    end

    def add_source_to_list(source, list)
      list.unshift(source).uniq!
      source
    end

    def source_list_for(source)
      case source
      when Source::Git          then git_sources
      when Source::Path         then path_sources
      when Source::Rubygems     then rubygems_sources
      when Plugin::API::Source  then plugin_sources
      else raise ArgumentError, "Invalid source: #{source.inspect}"
      end
    end

    def combine_rubygems_sources
      Source::Rubygems.new("remotes" => rubygems_remotes)
    end

    def warn_on_git_protocol(source)
      return if Bundler.settings["git.allow_insecure"]

      if source.uri =~ /^git\:/
        Bundler.ui.warn "The git source `#{source.uri}` uses the `git` protocol, " \
          "which transmits data without encryption. Disable this warning with " \
          "`bundle config set --local git.allow_insecure true`, or switch to the `https` " \
          "protocol to keep your data secure."
      end
    end

    def equal_sources?(lock_sources, replacement_sources)
      lock_sources.sort_by(&:to_s) == replacement_sources.sort_by(&:to_s)
    end

    def equal_source?(source, other_source)
      source == other_source
    end

    def equivalent_source?(source, other_source)
      return false unless Bundler.settings[:allow_deployment_source_credential_changes] && source.is_a?(Source::Rubygems)

      equivalent_rubygems_sources?([source], [other_source])
    end

    def equivalent_sources?(lock_sources, replacement_sources)
      return false unless Bundler.settings[:allow_deployment_source_credential_changes]

      lock_rubygems_sources, lock_other_sources = lock_sources.partition {|s| s.is_a?(Source::Rubygems) }
      replacement_rubygems_sources, replacement_other_sources = replacement_sources.partition {|s| s.is_a?(Source::Rubygems) }

      equivalent_rubygems_sources?(lock_rubygems_sources, replacement_rubygems_sources) && equal_sources?(lock_other_sources, replacement_other_sources)
    end

    def equivalent_rubygems_sources?(lock_sources, replacement_sources)
      actual_remotes = replacement_sources.map(&:remotes).flatten.uniq
      lock_sources.all? {|s| s.equivalent_remotes?(actual_remotes) }
    end
  end
end
