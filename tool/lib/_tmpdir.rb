template = "rubytest."

# This path is only for tests.
# Assume the directory by these environment variables are safe.
base = [ENV["TMPDIR"], ENV["TMP"], "/tmp"].find do |tmp|
  next unless tmp and tmp.size <= 50 and File.directory?(tmp)
  # On macOS, the default TMPDIR is very long, in spite of UNIX socket
  # path length being limited.
  #
  # Also Rubygems creates its own temporary directory per tests, and
  # some tests copy the full path of gemhome there.  In that case, the
  # path contains both temporary names twice, and can exceed path name
  # limit very easily.
  tmp
end
begin
  tmpdir = File.join(base, template + Random.new_seed.to_s(36)[-6..-1])
  Dir.mkdir(tmpdir, 0o700)
rescue Errno::EEXIST
  retry
end
# warn "tmpdir(#{tmpdir.size}) = #{tmpdir}"

pid = $$
END {
  if pid == $$
    begin
      Dir.rmdir(tmpdir)
    rescue Errno::ENOENT
    rescue Errno::ENOTEMPTY
      require_relative "colorize"
      colorize = Colorize.new
      ls = Struct.new(:colorize) do
        def mode_inspect(m, s)
          [
            (m & 0o4 == 0 ? ?- : ?r),
            (m & 0o2 == 0 ? ?- : ?w),
            (m & 0o1 == 0 ? (s ? s.upcase : ?-) : (s || ?x)),
          ]
        end
        def decorate_path(path, st)
          case
          when st.directory?
            color = "bold;blue"
            type = "/"
          when st.symlink?
            color = "bold;cyan"
            # type = "@"
          when st.executable?
            color = "bold;green"
            type = "*"
          when path.end_with?(".gem")
            color = "green"
          end
          colorize.decorate(path, color) + (type || "")
        end
        def list_tree(parent, indent = "", &block)
          children = Dir.children(parent).map do |child|
            [child, path = File.join(parent, child), File.lstat(path)]
          end
          nlink_width = children.map {|child, path, st| st.nlink}.max.to_s.size
          size_width = children.map {|child, path, st| st.size}.max.to_s.size

          children.each do |child, path, st|
            m = st.mode
            m = [
              (st.file? ? ?- : st.ftype[0]),
              mode_inspect(m >> 6, (?s unless m & 04000 == 0)),
              mode_inspect(m >> 3, (?s unless m & 02000 == 0)),
              mode_inspect(m,      (?t unless m & 01000 == 0)),
            ].join("")
            warn sprintf("%s* %s %*d %*d %s % s%s",
                         indent, m, nlink_width, st.nlink, size_width, st.size,
                         st.mtime.to_s, decorate_path(child,  st),
                         (" -> " + decorate_path(File.readlink(path), File.stat(path)) if
                           st.symlink?))
            if st.directory?
              list_tree(File.join(parent, child), indent + "  ", &block)
            end
            yield path, st if block
          end
        end
      end.new(colorize)
      warn colorize.notice("Children under ")+colorize.fail(tmpdir)+":"
      Dir.chdir(tmpdir) do
        ls.list_tree(".") do |path, st|
          if st.directory?
            Dir.rmdir(path)
          else
            File.unlink(path)
          end
        end
      end
      require "fileutils"
      FileUtils.rm_rf(tmpdir)
    end
  end
}

ENV["TMPDIR"] = ENV["SPEC_TEMP_DIR"] = ENV["GEM_TEST_TMPDIR"] = tmpdir
