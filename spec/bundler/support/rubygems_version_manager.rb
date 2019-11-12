# frozen_string_literal: true

require "pathname"
require_relative "helpers"
require_relative "path"

class RubygemsVersionManager
  include Spec::Helpers
  include Spec::Path

  def initialize(env_version)
    @env_version = env_version
  end

  def switch
    return if use_system?

    unrequire_rubygems_if_needed

    switch_local_copy_if_needed

    prepare_environment
  end

private

  def use_system?
    @env_version.nil?
  end

  def unrequire_rubygems_if_needed
    return unless rubygems_unrequire_needed?

    require "rbconfig"

    ruby = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"])
    ruby << RbConfig::CONFIG["EXEEXT"]

    cmd = [ruby, $0, *ARGV].compact
    cmd[1, 0] = "--disable-gems"

    exec(ENV, *cmd)
  end

  def switch_local_copy_if_needed
    return unless local_copy_switch_needed?

    Dir.chdir(local_copy_path) do
      sys_exec!("git remote update")
      sys_exec!("git checkout #{target_tag_version} --quiet")
    end
  end

  def prepare_environment
    $:.unshift File.expand_path("lib", local_copy_path)
  end

  def rubygems_unrequire_needed?
    defined?(Gem::VERSION) && Gem::VERSION != target_gem_version
  end

  def local_copy_switch_needed?
    !env_version_is_path? && target_gem_version != local_copy_version
  end

  def target_gem_version
    @target_gem_version ||= resolve_target_gem_version
  end

  def target_tag_version
    @target_tag_version ||= resolve_target_tag_version
  end

  def local_copy_version
    gemspec_contents = File.read(local_copy_path.join("lib/rubygems.rb"))
    version_regexp = /VERSION = ["'](.*)["']/

    version_regexp.match(gemspec_contents)[1]
  end

  def local_copy_path
    @local_copy_path ||= resolve_local_copy_path
  end

  def resolve_local_copy_path
    return expanded_env_version if env_version_is_path?

    rubygems_path = root.join("tmp/rubygems")

    unless rubygems_path.directory?
      rubygems_path.parent.mkpath
      sys_exec!("git clone https://github.com/rubygems/rubygems.git #{rubygems_path}")
    end

    rubygems_path
  end

  def env_version_is_path?
    expanded_env_version.directory?
  end

  def expanded_env_version
    @expanded_env_version ||= Pathname.new(@env_version).expand_path(root)
  end

  def resolve_target_tag_version
    return "v#{@env_version}" if @env_version.match(/^\d/)

    return "master" if @env_version == master_gem_version

    @env_version
  end

  def resolve_target_gem_version
    return local_copy_version if env_version_is_path?

    return @env_version[1..-1] if @env_version.match(/^v/)

    return master_gem_version if @env_version == "master"

    @env_version
  end

  def master_gem_version
    "3.1.0.pre1"
  end
end
