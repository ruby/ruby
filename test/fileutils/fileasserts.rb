# $Id$

module Test
  module Unit
    module Assertions   # redefine

      def assert_same_file(from, to)
        _wrap_assertion {
          assert_block("file #{from} != #{to}") {
            File.read(from) == File.read(to)
          }
        }
      end

      def assert_same_entry(from, to)
        _wrap_assertion {
          assert_block("entry #{from} != #{to}") {
            a = File.stat(from)
            b = File.stat(to)

            a.mode == b.mode and
            #a.atime == b.atime and
            a.mtime == b.mtime and
            a.uid == b.uid and
            a.gid == b.gid
          }
        }
      end

      def assert_file_exist(path)
        _wrap_assertion {
          assert_block("file not exist: #{path}") {
            File.exist?(path)
          }
        }
      end

      def assert_file_not_exist(path)
        _wrap_assertion {
          assert_block("file not exist: #{path}") {
            not File.exist?(path)
          }
        }
      end

      def assert_directory(path)
        _wrap_assertion {
          assert_block("is not directory: #{path}") {
            File.directory?(path)
          }
        }
      end

      def assert_symlink(path)
        _wrap_assertion {
          assert_block("is not a symlink: #{path}") {
            File.symlink?(path)
          }
        }
      end

      def assert_not_symlink(path)
        _wrap_assertion {
          assert_block("is a symlink: #{path}") {
            not File.symlink?(path)
          }
        }
      end

    end
  end
end
