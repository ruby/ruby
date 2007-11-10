require 'fileutils'
require 'rubygems/command'
require 'rubygems/format'
require 'rubygems/installer'
require 'rubygems/version_option'

class Gem::Commands::PristineCommand < Gem::Command

  include Gem::VersionOption

  def initialize
    super 'pristine',
          'Restores installed gems to pristine condition from files located in the gem cache',
          :version => Gem::Requirement.default

    add_option('--all',
               'Restore all installed gems to pristine',
               'condition') do |value, options|
      options[:all] = value
    end

    add_version_option('restore to', 'pristine condition')
  end

  def arguments # :nodoc:
    "GEMNAME       gem to restore to pristine condition (unless --all)"
  end

  def defaults_str # :nodoc:
    "--all"
  end

  def description # :nodoc:
    <<-EOF
The pristine command compares the installed gems with the contents of the
cached gem and restores any files that don't match the cached gem's copy.

If you have made modifications to your installed gems, the pristine command
will revert them.  After all the gem's files have been checked all bin stubs
for the gem are regenerated.

If the cached gem cannot be found, you will need to use `gem install` to
revert the gem.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [args]"
  end

  def execute
    gem_name = nil

    specs = if options[:all] then
              Gem::SourceIndex.from_installed_gems.map do |name, spec|
                spec
              end
            else
              gem_name = get_one_gem_name
              Gem::SourceIndex.from_installed_gems.search(gem_name,
                                                          options[:version])
            end

    if specs.empty? then
      raise Gem::Exception,
            "Failed to find gem #{gem_name} #{options[:version]}"
    end

    install_dir = Gem.dir # TODO use installer option

    raise Gem::FilePermissionError.new(install_dir) unless
      File.writable?(install_dir)

    say "Restoring gem(s) to pristine condition..."

    specs.each do |spec|
      gem = Dir[File.join(Gem.dir, 'cache', "#{spec.full_name}.gem")].first

      if gem.nil? then
        alert_error "Cached gem for #{spec.full_name} not found, use `gem install` to restore"
        next
      end

      # TODO use installer options
      installer = Gem::Installer.new gem, :wrappers => true

      gem_file = File.join install_dir, "cache", "#{spec.full_name}.gem"

      security_policy = nil # TODO use installer option

      format = Gem::Format.from_file_by_path gem_file, security_policy

      target_directory = File.join(install_dir, "gems", format.spec.full_name)
      target_directory.untaint

      pristine_files = format.file_entries.collect { |data| data[0]["path"] }
      file_map = {}

      format.file_entries.each do |entry, file_data|
        file_map[entry["path"]] = file_data
      end

      Dir.chdir target_directory do
        deployed_files = Dir.glob(File.join("**", "*")) +
                         Dir.glob(File.join("**", ".*"))

        pristine_files = pristine_files.map { |f| File.expand_path f }
        deployed_files = deployed_files.map { |f| File.expand_path f }

        to_redeploy = (pristine_files - deployed_files)
        to_redeploy = to_redeploy.map { |path| path.untaint}

        if to_redeploy.length > 0 then
          say "Restoring #{to_redeploy.length} file#{to_redeploy.length == 1 ? "" : "s"} to #{spec.full_name}..."

          to_redeploy.each do |path|
            say "  #{path}"
            FileUtils.mkdir_p File.dirname(path)
            File.open(path, "wb") do |out|
              out.write file_map[path]
            end
          end
        else
          say "#{spec.full_name} is in pristine condition"
        end
      end

      installer.generate_bin
    end
  end

end

