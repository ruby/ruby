# frozen_string_literal: true
module Bundler
  class SourceList
    attr_reader :path_sources,
      :git_sources,
      :plugin_sources

    def initialize
      @path_sources       = []
      @git_sources        = []
      @plugin_sources     = []
      @rubygems_aggregate = Source::Rubygems.new
      @rubygems_sources   = []
    end

    def add_path_source(options = {})
      if options["gemspec"]
        add_source_to_list Source::Gemspec.new(options), path_sources
      else
        add_source_to_list Source::Path.new(options), path_sources
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

    def add_rubygems_remote(uri)
      @rubygems_aggregate.add_remote(uri)
      @rubygems_aggregate
    end

    def rubygems_sources
      @rubygems_sources + [@rubygems_aggregate]
    end

    def rubygems_remotes
      rubygems_sources.map(&:remotes).flatten.uniq
    end

    def all_sources
      path_sources + git_sources + plugin_sources + rubygems_sources
    end

    def get(source)
      source_list_for(source).find {|s| source == s }
    end

    def lock_sources
      lock_sources = (path_sources + git_sources + plugin_sources).sort_by(&:to_s)
      lock_sources << combine_rubygems_sources
    end

    def replace_sources!(replacement_sources)
      return true if replacement_sources.empty?

      [path_sources, git_sources, plugin_sources].each do |source_list|
        source_list.map! do |source|
          replacement_sources.find {|s| s == source } || source
        end
      end

      replacement_rubygems =
        replacement_sources.detect {|s| s.is_a?(Source::Rubygems) }
      @rubygems_aggregate = replacement_rubygems if replacement_rubygems

      # Return true if there were changes
      lock_sources.to_set != replacement_sources.to_set ||
        rubygems_remotes.to_set != replacement_rubygems.remotes.to_set
    end

    def cached!
      all_sources.each(&:cached!)
    end

    def remote!
      all_sources.each(&:remote!)
    end

    def rubygems_primary_remotes
      @rubygems_aggregate.remotes
    end

  private

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
          "`bundle config git.allow_insecure true`, or switch to the `https` " \
          "protocol to keep your data secure."
      end
    end
  end
end
