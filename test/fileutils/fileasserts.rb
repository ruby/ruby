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

      def assert_file_exist( file )
        _wrap_assertion {
          assert_block("file not exist: #{file}") {
            File.exist?(file)
          }
        }
      end

      def assert_file_not_exist( file )
        _wrap_assertion {
          assert_block("file not exist: #{file}") {
            not File.exist?(file)
          }
        }
      end

      def assert_is_directory( file )
        _wrap_assertion {
          assert_block("is not directory: #{file}") {
            File.directory?(file)
          }
        }
      end

    end
  end
end
