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

    switch_local_copy_if_needed

    reexec_if_needed
  end

private

  def use_system?
    @source.nil?
  end

  def reexec_if_needed
    return unless rubygems_unrequire_needed?

    require "rbconfig"

    ruby = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"])
    ruby << RbConfig::CONFIG["EXEEXT"]

    cmd = [ruby, $0, *ARGV].compact

    ENV["RUBYOPT"] = "-I#{local_copy_path.join("lib")} #{ENV["RUBYOPT"]}"

    exec(ENV, *cmd)
  end

  def switch_local_copy_if_needed
    return unless local_copy_switch_needed?

    Dir.chdir(local_copy_path) do
      sys_exec!("git remote update")
      sys_exec!("git checkout #{target_tag} --quiet")
    end

    ENV["RGV"] = local_copy_path.to_s
  end

  def rubygems_unrequire_needed?
    !$LOADED_FEATURES.include?(local_copy_path.join("lib/rubygems.rb").to_s)
  end

  def local_copy_switch_needed?
    !source_is_path? && target_tag != local_copy_tag
  end

  def target_tag
    @target_tag ||= resolve_target_tag
  end

  def local_copy_tag
    Dir.chdir(local_copy_path) do
      sys_exec!("git rev-parse --abbrev-ref HEAD")
    end
  end

  def local_copy_path
    @local_copy_path ||= resolve_local_copy_path
  end

  def resolve_local_copy_path
    return expanded_source if source_is_path?

    rubygems_path = root.join("tmp/rubygems")

    unless rubygems_path.directory?
      rubygems_path.parent.mkpath
      sys_exec!("git clone https://github.com/rubygems/rubygems.git #{rubygems_path}")
    end

    rubygems_path
  end

  def source_is_path?
    expanded_source.directory?
  end

  def expanded_source
    @expanded_source ||= Pathname.new(@source).expand_path(root)
  end

  def resolve_target_tag
    return "v#{@source}" if @source.match(/^\d/)

    @source
  end
end
