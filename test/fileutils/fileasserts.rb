# frozen_string_literal: true
# $Id$

module Test
  module Unit
    module FileAssertions
      def assert_same_file(from, to, message=nil)
        assert_equal(File.read(from), File.read(to), "file #{from} != #{to}#{message&&': '}#{message||''}")
      end

      def assert_same_entry(from, to, message=nil)
        a = File.stat(from)
        b = File.stat(to)
        msg = "#{message&&': '}#{message||''}"
        assert_equal a.mode, b.mode, "mode #{a.mode} != #{b.mode}#{msg}"
        #assert_equal a.atime, b.atime
        assert_equal_timestamp a.mtime, b.mtime, "mtime #{a.mtime} != #{b.mtime}#{msg}"
        assert_equal a.uid, b.uid, "uid #{a.uid} != #{b.uid}#{msg}"
        assert_equal a.gid, b.gid, "gid #{a.gid} != #{b.gid}#{msg}"
      end

      def assert_file_exist(path, message=nil)
        assert(File.exist?(path), "file not exist: #{path}#{message&&': '}#{message||''}")
      end

      def assert_file_not_exist(path, message=nil)
        assert(!File.exist?(path), "file exist: #{path}#{message&&': '}#{message||''}")
      end

      def assert_directory(path, message=nil)
        assert(File.directory?(path), "is not directory: #{path}#{message&&': '}#{message||''}")
      end

      def assert_symlink(path, message=nil)
        assert(File.symlink?(path), "is not a symlink: #{path}#{message&&': '}#{message||''}")
      end

      def assert_not_symlink(path, message=nil)
        assert(!File.symlink?(path), "is a symlink: #{path}#{message&&': '}#{message||''}")
      end

      def assert_equal_time(expected, actual, message=nil)
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
        assert_equal(expected, actual, full_message)
      end

      def assert_equal_timestamp(expected, actual, message=nil)
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
        assert_equal(expected.tv_sec, actual.tv_sec, full_message)
      end

      def assert_filemode(expected, file, message=nil, mask: 07777)
        width = ('%o' % mask).size
        actual = File.stat(file).mode & mask
        assert expected == actual, <<EOT
File mode of "#{file}" unexpected:
 Expected: <#{'%0*o' % [width, expected]}>
   Actual: <#{'%0*o' % [width, actual]}>
EOT
      end

      def assert_equal_filemode(file1, file2, message=nil, mask: 07777)
        mode1, mode2 = [file1, file2].map { |file|
          File.stat(file).mode & mask
        }
        width = ('%o' % mask).size
        assert mode1 == mode2, <<EOT
File modes expected to be equal:
 <#{'%0*o' % [width, mode1]}>: "#{file1}"
 <#{'%0*o' % [width, mode2]}>: "#{file2}"
EOT
      end

      def assert_ownership_group(expected, file)
        actual = File.stat(file).gid
        assert expected == actual, <<EOT
File group ownership of "#{file}" unexpected:
 Expected: <#{expected}>
   Actual: <#{actual}>
EOT
      end

      def assert_ownership_user(expected, file)
        actual = File.stat(file).uid
        assert expected == actual, <<EOT
File user ownership of "#{file}" unexpected:
 Expected: <#{expected}>
   Actual: <#{actual}>
EOT
      end
    end
  end
end
