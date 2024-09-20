# frozen_string_literal: true

require_relative "options"
require_relative "env"
require_relative "subprocess"

class RubygemsVersionManager
  include Spec::Options
  include Spec::Env
  include Spec::Subprocess

  def initialize(source)
    @source = source
  end

  def switch
    return if use_system?

    assert_system_features_not_loaded!

    switch_local_copy_if_needed

    reexec_if_needed
  end

  def assert_system_features_not_loaded!
    at_exit do
      rubylibdir = RbConfig::CONFIG["rubylibdir"]

      rubygems_path = rubylibdir + "/rubygems"
      rubygems_default_path = rubygems_path + "/defaults"

      bundler_path = rubylibdir + "/bundler"

      bad_loaded_features = $LOADED_FEATURES.select do |loaded_feature|
        (loaded_feature.start_with?(rubygems_path) && !loaded_feature.start_with?(rubygems_default_path)) ||
          loaded_feature.start_with?(bundler_path)
      end

      errors = if bad_loaded_features.any?
        all_commands_output + "the following features were incorrectly loaded:\n#{bad_loaded_features.join("\n")}"
      end

      raise errors if errors
    end
  end

  private

  def use_system?
    @source.nil?
  end

  def reexec_if_needed
    return unless rubygems_unrequire_needed?

    require "rbconfig"

    cmd = [RbConfig.ruby, $0, *ARGV].compact

    ENV["RUBYOPT"] = opt_add("-I#{File.join(local_copy_path, "lib")}", opt_remove("--disable-gems", ENV["RUBYOPT"]))

    exec(ENV, *cmd)
  end

  def switch_local_copy_if_needed
    return unless local_copy_switch_needed?

    git("checkout #{target_tag}", local_copy_path)

    ENV["RGV"] = local_copy_path
  end

  def rubygems_unrequire_needed?
    require "rubygems"
    !$LOADED_FEATURES.include?(File.join(local_copy_path, "lib/rubygems.rb"))
  end

  def local_copy_switch_needed?
    !source_is_path? && target_tag != local_copy_tag
  end

  def target_tag
    @target_tag ||= resolve_target_tag
  end

  def local_copy_tag
    git("rev-parse --abbrev-ref HEAD", local_copy_path)
  end

  def local_copy_path
    @local_copy_path ||= resolve_local_copy_path
  end

  def resolve_local_copy_path
    return expanded_source if source_is_path?

    rubygems_path = File.join(source_root, "tmp/rubygems")

    unless File.directory?(rubygems_path)
      git("clone .. #{rubygems_path}", source_root)
    end

    rubygems_path
  end

  def source_is_path?
    File.directory?(expanded_source)
  end

  def expanded_source
    @expanded_source ||= File.expand_path(@source, source_root)
  end

  def source_root
    @source_root ||= File.expand_path(ruby_core? ? "../../.." : "../..", __dir__)
  end

  def resolve_target_tag
    return "v#{@source}" if @source.match?(/^\d/)

    @source
  end
end
