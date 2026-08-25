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
      base_slice = byteslice_at_char_boundary(basename, 254 - tmp_suffix.bytesize)
      tmp_path = File.join(dirname, ".#{base_slice}#{tmp_suffix}")

      # The temporary name is longer than the final one, so on Windows a
      # writable destination can still map to a path beyond the 260-character
      # MAX_PATH limit. Trim the random suffix first, keeping at least 8 hex
      # characters to avoid collisions, then shorten the basename if that is not
      # enough. Recomputing the basename from the trimmed suffix would just let
      # it grow back, so trim the already-sliced basename instead.
      if tmp_path.length >= 260 && Gem.win_platform?
        overflow = tmp_path.length - 259
        trim = [tmp_suffix.bytesize - (".tmp.".bytesize + 8), overflow].min
        tmp_suffix = tmp_suffix.byteslice(0, tmp_suffix.bytesize - trim)
        overflow -= trim
        base_slice = byteslice_at_char_boundary(base_slice, [base_slice.bytesize - overflow, 0].max) if overflow > 0
        tmp_path = File.join(dirname, ".#{base_slice}#{tmp_suffix}")
      end

      flags = File::RDWR | File::CREAT | File::EXCL | File::BINARY
      flags |= File::SHARE_DELETE if defined?(File::SHARE_DELETE)

      renamed = false
      temp_file = File.open(tmp_path, flags)

      begin
        temp_file.binmode
        if old_stat
          # Set correct permissions on new file
          begin
            temp_file.chown(old_stat.uid, old_stat.gid)
            # This operation will affect filesystem ACL's
            temp_file.chmod(old_stat.mode)
          rescue Errno::EPERM, Errno::EACCES
            # Changing file ownership failed, moving on.
          end
        end

        return_val = yield temp_file

        # Any data still buffered is handed to the filesystem on close, so a
        # failing flush must surface while the destination is still intact.
        # That means closing the temporary file before the rename. Note this
        # does not fsync, so the write is atomic but not crash durable.
        temp_file.close
        File.rename(tmp_path, file_name)
        renamed = true

        return_val
      ensure
        unless renamed
          begin
            temp_file.close
          rescue StandardError
            nil
          ensure
            # The unlink runs from an ensure so that a non-StandardError raised by
            # the close above, a second Ctrl-C for instance, still reaches it. An
            # interrupt landing on the unlink itself is not covered.
            begin
              File.unlink(tmp_path)
            rescue StandardError
              nil
            end
          end
        end
      end
    end

    # Returns the longest prefix of string that is at most max_bytesize bytes
    # and ends on a character boundary. A string that is invalid in its own
    # encoding would be cut back to its last valid prefix, discarding an
    # unbounded part of the name, so it is sliced as raw bytes instead and can
    # still be cut mid-character.
    def self.byteslice_at_char_boundary(string, max_bytesize)
      sliced = string.byteslice(0, max_bytesize)
      sliced.scrub!("") if string.valid_encoding?
      sliced
    end
    private_class_method :byteslice_at_char_boundary
  end
end
