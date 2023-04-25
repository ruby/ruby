require "tmpdir"
require "fileutils"

if (tmpdir = Dir.mktmpdir("rubyspec_temp.")).size > 80
  # On macOS, the default TMPDIR is very long, inspite of UNIX socket
  # path length is limited.
  Dir.rmdir(tmpdir)
  tmpdir = Dir.mktmpdir("rubyspec_temp.", "/tmp")
end
# warn "tmpdir(#{tmpdir.size}) = #{tmpdir}"
END {FileUtils.rm_rf(tmpdir)}

ENV["TMPDIR"] = ENV["SPEC_TEMP_DIR"] = tmpdir
