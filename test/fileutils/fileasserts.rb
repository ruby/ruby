#
# test/fileutils/fileasserts.rb
#

module Test
  module Unit
    module Assertions   # redefine

      def assert_same_file( from, to )
        _wrap_assertion {
          assert_block("file #{from} != #{to}") {
            File.read(from) == File.read(to)
          }
        }
      end

      def assert_file_exist( path )
        _wrap_assertion {
          assert_block("file not exist: #{path}") {
            File.exist?(path)
          }
        }
      end

      def assert_file_not_exist( path )
        _wrap_assertion {
          assert_block("file not exist: #{path}") {
            not File.exist?(path)
          }
        }
      end

      def assert_directory( path )
        _wrap_assertion {
          assert_block("is not directory: #{path}") {
            File.directory?(path)
          }
        }
      end

      def assert_symlink( path )
        _wrap_assertion {
          assert_block("is no symlink: #{path}") {
            File.symlink?(path)
          }
        }
      end

    end
  end
end
