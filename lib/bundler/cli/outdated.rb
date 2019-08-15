# frozen_string_literal: true

module Bundler
  class CLI::Outdated
    attr_reader :options, :gems, :options_include_groups, :filter_options_patch, :sources, :strict
    attr_accessor :outdated_gems_by_groups, :outdated_gems_list

    def initialize(options, gems)
      @options = options
      @gems = gems
      @sources = Array(options[:source])

      @filter_options_patch = options.keys &
        %w[filter-major filter-minor filter-patch]

      @outdated_gems_by_groups = {}
      @outdated_gems_list = []

      @options_include_groups = [:group, :groups].any? do |v|
        options.keys.include?(v.to_s)
      end

      # the patch level options imply strict is also true. It wouldn't make
      # sense otherwise.
      @strict = options["filter-strict"] ||
        Bundler::CLI::Common.patch_level_options(options).any?
    end

    def run
      check_for_deployment_mode!

      gems.each do |gem_name|
        Bundler::CLI::Common.select_spec(gem_name)
      end

      Bundler.definition.validate_runtime!
      current_specs = Bundler.ui.silence { Bundler.definition.resolve }

      current_dependencies = Bundler.ui.silence do
        Bundler.load.dependencies.map {|dep| [dep.name, dep] }.to_h
      end

      definition = if gems.empty? && sources.empty?
        # We're doing a full update
        Bundler.definition(true)
      else
        Bundler.definition(:gems => gems, :sources => sources)
      end

      Bundler::CLI::Common.configure_gem_version_promoter(
        Bundler.definition,
        options
      )

      definition_resolution = proc do
        options[:local] ? definition.resolve_with_cache! : definition.resolve_remotely!
      end

      if options[:parseable]
        Bundler.ui.silence(&definition_resolution)
      else
        definition_resolution.call
      end

      Bundler.ui.info ""

      # Loop through the current specs
      gemfile_specs, dependency_specs = current_specs.partition do |spec|
        current_dependencies.key? spec.name
      end

      specs = if options["only-explicit"]
        gemfile_specs
      else
        gemfile_specs + dependency_specs
      end

      specs.sort_by(&:name).each do |current_spec|
        next if !gems.empty? && !gems.include?(current_spec.name)

        dependency = current_dependencies[current_spec.name]
        active_spec = retrieve_active_spec(definition, current_spec)

        next if active_spec.nil?
        next if filter_options_patch.any? &&
          !update_present_via_semver_portions(current_spec, active_spec, options)

        gem_outdated = Gem::Version.new(active_spec.version) > Gem::Version.new(current_spec.version)
        next unless gem_outdated || (current_spec.git_version != active_spec.git_version)
        groups = nil
        if dependency && !options[:parseable]
          groups = dependency.groups.join(", ")
        end

        outdated_gems_list << { :active_spec => active_spec,
                                :current_spec => current_spec,
                                :dependency => dependency,
                                :groups => groups }

        outdated_gems_by_groups[groups] ||= []
        outdated_gems_by_groups[groups] << outdated_gems_list[-1]
      end

      if outdated_gems_list.empty?
        display_nothing_outdated_message
      else
        unless options[:parseable]
          Bundler.ui.info(header_outdated_message)
        end

        if options_include_groups
          ordered_groups = outdated_gems_by_groups.keys.compact.sort
          ordered_groups.insert(0, nil).each do |groups|
            gems = outdated_gems_by_groups[groups]
            contains_group = if groups
              groups.split(", ").include?(options[:group])
            else
              options[:group] == "group"
            end

            next if (!options[:groups] && !contains_group) || gems.nil?

            unless options[:parseable]
              Bundler.ui.info(header_group_message(groups))
            end

            print_gems(gems)
          end
        else
          print_gems(outdated_gems_list)
        end

        exit 1
      end
    end

  private

    def groups_text(group_text, groups)
      "#{group_text}#{groups.split(",").size > 1 ? "s" : ""} \"#{groups}\""
    end

    def header_outdated_message
      if options[:pre]
        "Outdated gems included in the bundle (including pre-releases):"
      else
        "Outdated gems included in the bundle:"
      end
    end

    def header_group_message(groups)
      if groups
        "===== #{groups_text("Group", groups)} ====="
      else
        "===== Without group ====="
      end
    end

    def nothing_outdated_message
      if filter_options_patch.any?
        display = filter_options_patch.map do |o|
          o.sub("filter-", "")
        end.join(" or ")

        "No #{display} updates to display.\n"
      else
        "Bundle up to date!\n"
      end
    end

    def retrieve_active_spec(definition, current_spec)
      return unless current_spec.match_platform(Bundler.local_platform)

      if strict
        active_spec = definition.find_resolved_spec(current_spec)
      else
        active_specs = definition.find_indexed_specs(current_spec)
        if !current_spec.version.prerelease? && !options[:pre] && active_specs.size > 1
          active_specs.delete_if {|b| b.respond_to?(:version) && b.version.prerelease? }
        end
        active_spec = active_specs.last
      end

      active_spec
    end

    def display_nothing_outdated_message
      unless options[:parseable]
        Bundler.ui.info(nothing_outdated_message)
      end
    end

    def print_gems(gems_list)
      gems_list.each do |gem|
        print_gem(
          gem[:current_spec],
          gem[:active_spec],
          gem[:dependency],
          gem[:groups],
        )
      end
    end

    def print_gem(current_spec, active_spec, dependency, groups)
      spec_version = "#{active_spec.version}#{active_spec.git_version}"
      spec_version += " (from #{active_spec.loaded_from})" if Bundler.ui.debug? && active_spec.loaded_from
      current_version = "#{current_spec.version}#{current_spec.git_version}"

      if dependency && dependency.specific?
        dependency_version = %(, requested #{dependency.requirement})
      end

      spec_outdated_info = "#{active_spec.name} (newest #{spec_version}, " \
        "installed #{current_version}#{dependency_version})"

      output_message = if options[:parseable]
        spec_outdated_info.to_s
      elsif options_include_groups || !groups
        "  * #{spec_outdated_info}"
      else
        "  * #{spec_outdated_info} in #{groups_text("group", groups)}"
      end

      Bundler.ui.info output_message.rstrip
    end

    def check_for_deployment_mode!
      return unless Bundler.frozen_bundle?
      suggested_command = if Bundler.settings.locations("frozen")[:global]
        "bundle config unset frozen"
      elsif Bundler.settings.locations("deployment").keys.&([:global, :local]).any?
        "bundle config unset deployment"
      else
        "bundle install --no-deployment"
      end
      raise ProductionError, "You are trying to check outdated gems in " \
        "deployment mode. Run `bundle outdated` elsewhere.\n" \
        "\nIf this is a development machine, remove the " \
        "#{Bundler.default_gemfile} freeze" \
        "\nby running `#{suggested_command}`."
    end

    def update_present_via_semver_portions(current_spec, active_spec, options)
      current_major = current_spec.version.segments.first
      active_major = active_spec.version.segments.first

      update_present = false
      update_present = active_major > current_major if options["filter-major"]

      if !update_present && (options["filter-minor"] || options["filter-patch"]) && current_major == active_major
        current_minor = get_version_semver_portion_value(current_spec, 1)
        active_minor = get_version_semver_portion_value(active_spec, 1)

        update_present = active_minor > current_minor if options["filter-minor"]

        if !update_present && options["filter-patch"] && current_minor == active_minor
          current_patch = get_version_semver_portion_value(current_spec, 2)
          active_patch = get_version_semver_portion_value(active_spec, 2)

          update_present = active_patch > current_patch
        end
      end

      update_present
    end

    def get_version_semver_portion_value(spec, version_portion_index)
      version_section = spec.version.segments[version_portion_index, 1]
      version_section.to_a[0].to_i
    end
  end
end
