# frozen_string_literal: true
require "bundler/cli/common"

module Bundler
  class CLI::Pristine
    def run
      definition = Bundler.definition
      definition.validate_runtime!
      installer = Bundler::Installer.new(Bundler.root, definition)

      Bundler.load.specs.each do |spec|
        next if spec.name == "bundler" # Source::Rubygems doesn't install bundler

        gem_name = "#{spec.name} (#{spec.version}#{spec.git_version})"
        gem_name += " (#{spec.platform})" if !spec.platform.nil? && spec.platform != Gem::Platform::RUBY

        case source = spec.source
        when Source::Rubygems
          cached_gem = spec.cache_file
          unless File.exist?(cached_gem)
            Bundler.ui.error("Failed to pristine #{gem_name}. Cached gem #{cached_gem} does not exist.")
            next
          end
        when Source::Git
          source.remote!
        else
          Bundler.ui.warn("Cannot pristine #{gem_name}. Gem is sourced from local path.")
          next
        end
        FileUtils.rm_rf spec.full_gem_path

        Bundler::GemInstaller.new(spec, installer, false, 0, true).install_from_spec
      end
    end
  end
end
