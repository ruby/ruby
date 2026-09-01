# frozen_string_literal: true

##
# Helper methods for both Gem::Installer and Gem::Uninstaller

module Gem::InstallerUninstallerUtils
  def regenerate_plugins_for(spec, plugins_dir)
    plugins = spec.plugins
    return if plugins.empty?

    require "pathname"

    plugin_script_dir = plugin_stub_dir_for(spec, plugins_dir)

    FileUtils.mkdir_p plugin_script_dir
    remove_plugins_for(spec, plugins_dir)

    plugins.each do |plugin|
      plugin_script_path = File.join plugin_script_dir, "#{spec.name}_plugin#{File.extname(plugin)}"

      File.open plugin_script_path, "wb" do |file|
        file.puts "require_relative '#{Pathname.new(plugin).relative_path_from(Pathname.new(plugin_script_dir))}'"
      end

      verbose plugin_script_path
    end
  end

  def remove_plugins_for(spec, plugins_dir)
    FileUtils.rm_f Gem::Util.glob_files_in_dir("#{spec.name}#{Gem.plugin_suffix_pattern}", plugins_dir)
    FileUtils.rm_f Gem::Util.glob_files_in_dir("#{spec.name}#{Gem.plugin_suffix_pattern}", ruby_abi_plugin_dir_for(spec, plugins_dir))
  end

  private

  def plugin_stub_dir_for(spec, plugins_dir)
    ruby_abi = spec.to_spec.ruby_abi if Gem::ContentAddress.match?(spec.content_address)
    ruby_abi ? File.join(plugins_dir, ruby_abi) : plugins_dir
  end

  def ruby_abi_plugin_dir_for(spec, plugins_dir)
    ruby_abi = spec.to_spec.ruby_abi if Gem::ContentAddress.match?(spec.content_address)
    File.join plugins_dir, ruby_abi || Gem.ruby_abi
  end
end
