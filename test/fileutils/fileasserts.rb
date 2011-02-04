# $Id$

module Test
  module Unit
    module Assertions   # redefine

      def _wrap_assertion
        yield
      end

      def assert_block msg = nil
        assert yield, msg
      end

      def assert_same_file(from, to)
        _wrap_assertion {
          assert_block("file #{from} != #{to}") {
            File.read(from) == File.read(to)
          }
        }
      end

      def assert_same_entry(from, to)
        a = File.stat(from)
        b = File.stat(to)
        assert_equal a.mode, b.mode, "mode #{a.mode} != #{b.mode}"
        #assert_equal a.atime, b.atime
        assert_equal_timestamp a.mtime, b.mtime, "mtime #{a.mtime} != #{b.mtime}"
        assert_equal a.uid, b.uid, "uid #{a.uid} != #{b.uid}"
        assert_equal a.gid, b.gid, "gid #{a.gid} != #{b.gid}"
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

      def assert_equal_time(expected, actual, message=nil)
        _wrap_assertion {
	  expected_str = expected.to_s
	  actual_str = actual.to_s
	  if expected_str == actual_str
	    expected_str << " (nsec=#{expected.nsec})"
	    actual_str << " (nsec=#{actual.nsec})"
	  end
	  full_message = build_message(message, <<EOT)
<#{expected_str}> expected but was
<#{actual_str}>.
EOT
	  assert_block(full_message) { expected == actual }
        }
      end

      def assert_equal_timestamp(expected, actual, message=nil)
        _wrap_assertion {
	  expected_str = expected.to_s
	  actual_str = actual.to_s
	  if expected_str == actual_str
	    expected_str << " (nsec=#{expected.nsec})"
	    actual_str << " (nsec=#{actual.nsec})"
	  end
	  full_message = build_message(message, <<EOT)
<#{expected_str}> expected but was
<#{actual_str}>.
EOT
          # subsecond timestamp is not portable.
	  assert_block(full_message) { expected.tv_sec == actual.tv_sec }
        }
      end

    end
  end
end
