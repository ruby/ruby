require "tmpdir"
require "fileutils"

template = "rubytest."
if (tmpdir = Dir.mktmpdir(template)).size > 50 and File.directory?("/tmp")
  # On macOS, the default TMPDIR is very long, inspite of UNIX socket
  # path length is limited.
  # On Windows, UNIX socket is not available and no need to shorten
  # TMPDIR, otherwise assume "/tmp" always exists.
  Dir.rmdir(tmpdir)
  tmpdir = Dir.mktmpdir(template, "/tmp")
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
      mode_inspect = ->(m, s) {
        [
          (m & 0o4 == 0 ? ?- : ?r),
          (m & 0o2 == 0 ? ?- : ?w),
          (m & 0o1 == 0 ? (s ? s.upcase : ?-) : (s || ?x)),
        ]
      }
      filecolor = ->(st) {
        st.directory? ? "bold;blue" : st.symlink? ? "bold;cyan" : st.executable? ? "bold;green" : nil
      }
      list_tree = ->(parent, indent = "  ") {
        Dir.children(parent).each do |child|
          path = File.join(parent, child)
          st = File.lstat(path)
          m = st.mode
          m = [
            (st.file? ? ?- : st.ftype[0]),
            mode_inspect[m >> 6, (?s unless m & 04000 == 0)],
            mode_inspect[m >> 3, (?s unless m & 02000 == 0)],
            mode_inspect[m,      (?t unless m & 01000 == 0)],
          ].join("")
          warn [
            indent, m, st.nlink, st.size, st.mtime,
            colorize.decorate(child,  filecolor[st]),
            (["->", colorize.cyan(File.readlink(path))] if st.symlink?),
          ].compact.join(" ")
          if st.directory?
            list_tree[File.join(parent, child), indent + "  "]
          end
        end
      }
      warn colorize.notice("Children under ")+colorize.fail(tmpdir)+":"
      list_tree[tmpdir]
      FileUtils.rm_rf(tmpdir)
    end
  end
}

ENV["TMPDIR"] = ENV["SPEC_TEMP_DIR"] = ENV["GEM_TEST_TMPDIR"] = tmpdir
