# frozen_string_literal: true

require "pathname"
require_relative "helpers"
require_relative "path"

class RubygemsVersionManager
  include Spec::Helpers
  include Spec::Path

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

    ENV["RUBYOPT"] = opt_add("-I#{local_copy_path.join("lib")}", opt_remove("--disable-gems", ENV["RUBYOPT"]))

    exec(ENV, *cmd)
  end

  def switch_local_copy_if_needed
    return unless local_copy_switch_needed?

    sys_exec("git checkout #{target_tag}", dir: local_copy_path)

    ENV["RGV"] = local_copy_path.to_s
  end

  def rubygems_unrequire_needed?
    require "rubygems"
    !$LOADED_FEATURES.include?(local_copy_path.join("lib/rubygems.rb").to_s)
  end

  def local_copy_switch_needed?
    !source_is_path? && target_tag != local_copy_tag
  end

  def target_tag
    @target_tag ||= resolve_target_tag
  end

  def local_copy_tag
    sys_exec("git rev-parse --abbrev-ref HEAD", dir: local_copy_path)
  end

  def local_copy_path
    @local_copy_path ||= resolve_local_copy_path
  end

  def resolve_local_copy_path
    return expanded_source if source_is_path?

    rubygems_path = source_root.join("tmp/rubygems")

    unless rubygems_path.directory?
      sys_exec("git clone .. #{rubygems_path}", dir: source_root)
    end

    rubygems_path
  end

  def source_is_path?
    expanded_source.directory?
  end

  def expanded_source
    @expanded_source ||= Pathname.new(@source).expand_path(source_root)
  end

  def resolve_target_tag
    return "v#{@source}" if @source.match?(/^\d/)

    @source
  end
end
