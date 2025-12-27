# frozen_string_literal: true

# Based on ActiveSupport's AtomicFile implementation
# Copyright (c) David Heinemeier Hansson
# https://github.com/rails/rails/blob/main/activesupport/lib/active_support/core_ext/file/atomic.rb
# Licensed under the MIT License

module Gem
  class AtomicFileWriter
    ##
    # Write to a file atomically. Useful for situations where you don't
    # want other processes or threads to see half-written files.

    def self.open(file_name)
      temp_dir = File.dirname(file_name)
      require "tempfile" unless defined?(Tempfile)

      Tempfile.create(".#{File.basename(file_name)}", temp_dir) do |temp_file|
        temp_file.binmode
        return_value = yield temp_file
        temp_file.close

        original_permissions = if File.exist?(file_name)
          File.stat(file_name)
        else
          # If not possible, probe which are the default permissions in the
          # destination directory.
          probe_permissions_in(File.dirname(file_name))
        end

        # Set correct permissions on new file
        if original_permissions
          begin
            File.chown(original_permissions.uid, original_permissions.gid, temp_file.path)
            File.chmod(original_permissions.mode, temp_file.path)
          rescue Errno::EPERM, Errno::EACCES
            # Changing file ownership failed, moving on.
          end
        end

        # Overwrite original file with temp file
        File.rename(temp_file.path, file_name)
        return_value
      end
    end

    def self.probe_permissions_in(dir) # :nodoc:
      basename = [
        ".permissions_check",
        Thread.current.object_id,
        Process.pid,
        rand(1_000_000),
      ].join(".")

      file_name = File.join(dir, basename)
      File.open(file_name, "w") {}
      File.stat(file_name)
    rescue Errno::ENOENT
      nil
    ensure
      begin
        File.unlink(file_name) if File.exist?(file_name)
      rescue SystemCallError
      end
    end
  end
end
