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
      require "securerandom" unless defined?(SecureRandom)

      old_stat = begin
                   File.stat(file_name)
                 rescue SystemCallError
                   nil
                 end

      # Names can't be longer than 255B
      tmp_suffix = ".tmp.#{SecureRandom.hex}"
      dirname = File.dirname(file_name)
      basename = File.basename(file_name)
      tmp_path = File.join(dirname, ".#{basename.byteslice(0, 254 - tmp_suffix.bytesize)}#{tmp_suffix}")

      flags = File::RDWR | File::CREAT | File::EXCL | File::BINARY
      flags |= File::SHARE_DELETE if defined?(File::SHARE_DELETE)

      File.open(tmp_path, flags) do |temp_file|
        temp_file.binmode
        if old_stat
          # Set correct permissions on new file
          begin
            File.chown(old_stat.uid, old_stat.gid, temp_file.path)
            # This operation will affect filesystem ACL's
            File.chmod(old_stat.mode, temp_file.path)
          rescue Errno::EPERM, Errno::EACCES
            # Changing file ownership failed, moving on.
          end
        end

        return_val = yield temp_file
      rescue StandardError => error
        begin
          temp_file.close
        rescue StandardError
          nil
        end

        begin
          File.unlink(temp_file.path)
        rescue StandardError
          nil
        end

        raise error
      else
        begin
          File.rename(temp_file.path, file_name)
        rescue StandardError
          begin
            File.unlink(temp_file.path)
          rescue StandardError
          end

          raise
        end

        return_val
      end
    end
  end
end
