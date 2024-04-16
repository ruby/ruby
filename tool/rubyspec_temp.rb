require "tmpdir"
require "fileutils"

template = "rubyspec_temp."
if (tmpdir = Dir.mktmpdir(template)).size > 80
  # On macOS, the default TMPDIR is very long, inspite of UNIX socket
  # path length is limited.
  Dir.rmdir(tmpdir)
  tmpdir = Dir.mktmpdir(template, "/tmp")
end
# warn "tmpdir(#{tmpdir.size}) = #{tmpdir}"
END {FileUtils.rm_rf(tmpdir)}

ENV["TMPDIR"] = ENV["SPEC_TEMP_DIR"] = tmpdir
