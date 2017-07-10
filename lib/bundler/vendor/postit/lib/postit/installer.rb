module BundlerVendoredPostIt::PostIt
  class Installer
    def initialize(bundler_version)
      @bundler_version = bundler_version
    end

    def installed?
      if Gem::Specification.respond_to?(:find_by_name)
        !Gem::Specification.find_by_name('bundler', @bundler_version).nil?
      else
        requirement = Gem::Requirement.new(@bundler_version)
        Gem.source_index.gems.values.any? do |s|
          s.name == 'bundler' && requirement.satisfied_by?(s.version)
        end
      end
    rescue LoadError
      false
    end

    def install!
      return if installed?
      require 'rubygems/dependency_installer'
      installer = Gem::DependencyInstaller.new
      installer.install('bundler', @bundler_version)
      installer.installed_gems
    end
  end
end
