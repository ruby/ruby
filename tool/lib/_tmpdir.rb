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
    FileUtils.rm_rf(tmpdir)
  end
}

ENV["TMPDIR"] = ENV["SPEC_TEMP_DIR"] = ENV["GEM_TEST_TMPDIR"] = tmpdir
