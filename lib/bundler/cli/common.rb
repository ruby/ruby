# frozen_string_literal: true

module Bundler
  module CLI::Common
    def self.validate_cooldown!(value)
      # Without the flag the config file and BUNDLE_COOLDOWN decide, and those
      # only warn, so a typo left in a config file keeps the command usable.
      return warn_invalid_cooldown_setting if value.nil?
      return if value.is_a?(Integer) && value >= 0
      raise InvalidOption, "Expected `--cooldown` to be a non-negative integer, got #{value.inspect}"
    end

    # A cooldown value that cannot be read as a non-negative integer disables
    # the cooldown for every source, overriding any per-source `cooldown:` in
    # the Gemfile, so say so rather than letting the protection lapse quietly.
    def self.warn_invalid_cooldown_setting
      value = Bundler.settings.locations(:cooldown).values.first
      return if value.nil?

      days = Integer(value.to_s, exception: false)
      return if days && !days.negative?

      Bundler.ui.warn "Invalid cooldown value #{value.inspect}, so the cooldown is disabled for all sources. " \
                      "Expected a non-negative integer number of days."
    end

    def self.output_post_install_messages(messages)
      return if Bundler.settings["ignore_messages"]
      messages.to_a.each do |name, msg|
        print_post_install_message(name, msg) unless Bundler.settings["ignore_messages.#{name}"]
      end
    end

    def self.print_post_install_message(name, msg)
      Bundler.ui.confirm "Post-install message from #{name}:"
      Bundler.ui.info msg
    end

    def self.output_cooldown_skipped_summary(definition = Bundler.definition)
      skipped = definition.cooldown_skipped
      return if skipped.empty?

      Bundler.ui.info "The following gem versions were skipped by the cooldown setting:"
      skipped.each do |entry|
        days = entry[:available_in_days]
        Bundler.ui.info "  * #{entry[:name]} #{entry[:version]} (available in #{days} #{days == 1 ? "day" : "days"}), resolved #{entry[:resolved]} instead"
      end
    end

    def self.output_fund_metadata_summary
      return if Bundler.settings["ignore_funding_requests"]
      definition = Bundler.definition
      current_dependencies = definition.requested_dependencies
      current_specs = definition.specs

      count = current_dependencies.count {|dep| current_specs[dep.name].first.metadata.key?("funding_uri") }

      return if count.zero?

      intro = count > 1 ? "#{count} installed gems you directly depend on are" : "#{count} installed gem you directly depend on is"
      message = "#{intro} looking for funding.\n  Run `bundle fund` for details"
      Bundler.ui.info message
    end

    def self.output_without_groups_message(command)
      return if Bundler.settings[:without].empty?
      Bundler.ui.confirm without_groups_message(command)
    end

    def self.without_groups_message(command)
      command_in_past_tense = command == :install ? "installed" : "updated"
      groups = Bundler.settings[:without]
      "Gems in the #{verbalize_groups(groups)} were not #{command_in_past_tense}."
    end

    def self.verbalize_groups(groups)
      groups.map! {|g| "'#{g}'" }
      group_list = [groups[0...-1].join(", "), groups[-1..-1]].
        reject {|s| s.to_s.empty? }.join(" and ")
      group_str = groups.size == 1 ? "group" : "groups"
      "#{group_str} #{group_list}"
    end

    def self.select_spec(name, regex_match = nil)
      specs = []
      regexp = Regexp.new(name) if regex_match

      Bundler.definition.specs.each do |spec|
        return spec if spec.name == name
        specs << spec if regexp && spec.name.match?(regexp)
      end

      default_spec = default_gem_spec(name)
      specs << default_spec if default_spec

      case specs.count
      when 0
        dep_in_other_group = Bundler.definition.current_dependencies.find {|dep|dep.name == name }

        if dep_in_other_group
          raise GemNotFound, "Could not find gem '#{name}', because it's in the #{verbalize_groups(dep_in_other_group.groups)}, configured to be ignored."
        else
          raise GemNotFound, gem_not_found_message(name, Bundler.definition.dependencies)
        end
      when 1
        specs.first
      else
        ask_for_spec_from(specs)
      end
    rescue RegexpError
      raise GemNotFound, gem_not_found_message(name, Bundler.definition.dependencies)
    end

    def self.default_gem_spec(name)
      gem_spec = Gem::Specification.find_all_by_name(name).last
      gem_spec if gem_spec&.default_gem?
    end

    def self.ask_for_spec_from(specs)
      specs.each_with_index do |spec, index|
        Bundler.ui.info "#{index.succ} : #{spec.name}", true
      end
      Bundler.ui.info "0 : - exit -", true

      num = Bundler.ui.ask("> ").to_i
      num > 0 ? specs[num - 1] : nil
    end

    def self.gem_not_found_message(missing_gem_name, alternatives)
      message = "Could not find gem '#{missing_gem_name}'."
      alternate_names = alternatives.map {|a| a.respond_to?(:name) ? a.name : a }
      if alternate_names.include?(missing_gem_name.downcase)
        message += "\nDid you mean '#{missing_gem_name.downcase}'?"
      elsif defined?(DidYouMean::SpellChecker)
        suggestions = DidYouMean::SpellChecker.new(dictionary: alternate_names).correct(missing_gem_name)
        message += "\nDid you mean #{word_list(suggestions)}?" unless suggestions.empty?
      end
      message
    end

    def self.ensure_all_gems_in_lockfile!(names, locked_gems = Bundler.locked_gems)
      return unless locked_gems

      locked_names = locked_gems.specs.map(&:name).uniq
      names.-(locked_names).each do |g|
        raise GemNotFound, gem_not_found_message(g, locked_names)
      end
    end

    def self.configure_gem_version_promoter(definition, options)
      patch_level = patch_level_options(options)
      patch_level << :patch if patch_level.empty? && Bundler.settings[:prefer_patch]
      raise InvalidOption, "Provide only one of the following options: #{patch_level.join(", ")}" unless patch_level.length <= 1

      definition.gem_version_promoter.tap do |gvp|
        gvp.level = patch_level.first || :major
        gvp.strict = options[:strict] || options["filter-strict"]
        gvp.pre = options[:pre]
      end
    end

    def self.patch_level_options(options)
      [:major, :minor, :patch].select {|v| options.keys.include?(v.to_s) }
    end

    def self.clean_after_install?
      clean = Bundler.settings[:clean]
      return clean unless clean.nil?
      clean ||= Bundler.feature_flag.bundler_5_mode? && Bundler.settings[:path].nil?
      clean &&= !Bundler.use_system_gems?
      clean
    end

    # `bundle cache` copies the gem files out of the cache after installing, so
    # it asks to be skipped here and prunes once it is done.
    def self.prune(options = {})
      return if options["skip-prune"]

      categories = Bundler.settings[:prune]
      return if categories.empty?

      # Without a bundle path the cache is shared with RubyGems, so it holds gem
      # files Bundler never put there.
      if Bundler.use_system_gems?
        Bundler.ui.warn "The `prune` setting was ignored because this bundle installs into the system gem " \
                        "directory, which Bundler shares with RubyGems. Run `bundle config set path <dir>` to prune."
        return
      end

      Bundler.load.prune(categories)
    end

    def self.word_list(words)
      if words.empty?
        return ""
      end

      words = words.map {|word| "'#{word}'" }

      if words.length == 1
        return words[0]
      end

      [words[0..-2].join(", "), words[-1]].join(" or ")
    end
  end
end
