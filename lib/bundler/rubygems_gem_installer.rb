# frozen_string_literal: true

require "rubygems/installer"

module Bundler
  class RubyGemsGemInstaller < Gem::Installer
    unless respond_to?(:at)
      def self.at(*args)
        new(*args)
      end
    end

    def check_executable_overwrite(filename)
      # Bundler needs to install gems regardless of binstub overwriting
    end

    def pre_install_checks
      super && validate_bundler_checksum(options[:bundler_expected_checksum])
    end

    def build_extensions
      extension_cache_path = options[:bundler_extension_cache_path]
      return super unless extension_cache_path && extension_dir = Bundler.rubygems.spec_extension_dir(spec)

      extension_dir = Pathname.new(extension_dir)
      build_complete = SharedHelpers.filesystem_access(extension_cache_path.join("gem.build_complete"), :read, &:file?)
      if build_complete && !options[:force]
        SharedHelpers.filesystem_access(extension_dir.parent, &:mkpath)
        SharedHelpers.filesystem_access(extension_cache_path) do
          FileUtils.cp_r extension_cache_path, spec.extension_dir
        end
      else
        super
        if extension_dir.directory? # not made for gems without extensions
          SharedHelpers.filesystem_access(extension_cache_path.parent, &:mkpath)
          SharedHelpers.filesystem_access(extension_cache_path) do
            FileUtils.cp_r extension_dir, extension_cache_path
          end
        end
      end
    end

  private

    def validate_bundler_checksum(checksum)
      return true if Bundler.settings[:disable_checksum_validation]
      return true unless checksum
      return true unless source = @package.instance_variable_get(:@gem)
      return true unless source.respond_to?(:with_read_io)
      digest = source.with_read_io do |io|
        digest = SharedHelpers.digest(:SHA256).new
        digest << io.read(16_384) until io.eof?
        io.rewind
        send(checksum_type(checksum), digest)
      end
      unless digest == checksum
        raise SecurityError, <<-MESSAGE
          Bundler cannot continue installing #{spec.name} (#{spec.version}).
          The checksum for the downloaded `#{spec.full_name}.gem` does not match \
          the checksum given by the server. This means the contents of the downloaded \
          gem is different from what was uploaded to the server, and could be a potential security issue.

          To resolve this issue:
          1. delete the downloaded gem located at: `#{spec.gem_dir}/#{spec.full_name}.gem`
          2. run `bundle install`

          If you wish to continue installing the downloaded gem, and are certain it does not pose a \
          security issue despite the mismatching checksum, do the following:
          1. run `bundle config disable_checksum_validation true` to turn off checksum verification
          2. run `bundle install`

          (More info: The expected SHA256 checksum was #{checksum.inspect}, but the \
          checksum for the downloaded gem was #{digest.inspect}.)
          MESSAGE
      end
      true
    end

    def checksum_type(checksum)
      case checksum.length
      when 64 then :hexdigest!
      when 44 then :base64digest!
      else raise InstallError, "The given checksum for #{spec.full_name} (#{checksum.inspect}) is not a valid SHA256 hexdigest nor base64digest"
      end
    end

    def hexdigest!(digest)
      digest.hexdigest!
    end

    def base64digest!(digest)
      if digest.respond_to?(:base64digest!)
        digest.base64digest!
      else
        [digest.digest!].pack("m0")
      end
    end
  end
end
