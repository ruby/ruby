# frozen_string_literal: true

##
# Helper methods for both Gem::Installer and Gem::Uninstaller

module Gem::InstallerUninstallerUtils

  def regenerate_plugins_for(spec)
    spec.plugins.each do |plugin|
      plugin_script_path = File.join Gem.plugins_dir, "#{spec.name}_plugin#{File.extname(plugin)}"

      File.open plugin_script_path, 'wb' do |file|
        file.puts "require '#{plugin}'"
      end

      verbose plugin_script_path
    end
  end

  def remove_plugins_for(spec)
    FileUtils.rm_f Gem::Util.glob_files_in_dir("#{spec.name}#{Gem.plugin_suffix_pattern}", Gem.plugins_dir)
  end

end
