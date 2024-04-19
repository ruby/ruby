require "tmpdir"
require "fileutils"

template = "rubytest."
if (tmpdir = Dir.mktmpdir(template)).size > 50
  # On macOS, the default TMPDIR is very long, inspite of UNIX socket
  # path length is limited.
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
      warn colorize.notice("Children under ")+colorize.fail(tmpdir)+":"
      Dir.children(tmpdir).each do |child|
        path = File.join(tmpdir, child)
        st = File.lstat(path)
        m = st.mode
        m = [
          (st.file? ? ?- : st.ftype[0]),
          mode_inspect[m >> 6, (?s unless m & 04000 == 0)],
          mode_inspect[m >> 3, (?s unless m & 02000 == 0)],
          mode_inspect[m,      (?t unless m & 01000 == 0)],
        ].join("")
        warn [
          " ", m, st.nlink, st.size, st.mtime,
          colorize.decorate(child,  filecolor[st]),
          (["->", colorize.cyan(File.readlink(path))] if st.symlink?),
        ].compact.join(" ")
      end
      FileUtils.rm_rf(tmpdir)
    end
  end
}

ENV["TMPDIR"] = ENV["SPEC_TEMP_DIR"] = ENV["GEM_TEST_TMPDIR"] = tmpdir
