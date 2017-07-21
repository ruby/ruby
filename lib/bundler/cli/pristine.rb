# frozen_string_literal: true
require "bundler/cli/common"

module Bundler
  class CLI::Pristine
    def run
      Bundler.load.specs.each do |spec|
        next if spec.name == "bundler" # Source::Rubygems doesn't install bundler

        gem_name = "#{spec.name} (#{spec.version}#{spec.git_version})"
        gem_name += " (#{spec.platform})" if !spec.platform.nil? && spec.platform != Gem::Platform::RUBY

        case spec.source
        when Source::Rubygems
          cached_gem = spec.cache_file
          unless File.exist?(cached_gem)
            Bundler.ui.error("Failed to pristine #{gem_name}. Cached gem #{cached_gem} does not exist.")
            next
          end

          FileUtils.rm_rf spec.full_gem_path
          spec.source.install(spec, :force => true)
        when Source::Git
          git_source = spec.source
          git_source.remote!
          git_source.install(spec, :force => true)
        else
          Bundler.ui.warn("Cannot pristine #{gem_name}. Gem is sourced from local path.")
        end
      end
    end
  end
end
