require_relative "test_helper"
require "tmpdir"

class Dir_tmpdirTest < StdlibTest
  target Dir
  library "tmpdir"
  using hook.refinement

  def test_tmpdir
    Dir.tmpdir()
  end

  def test_mktmpdir
    Dir.mktmpdir()
    Dir.mktmpdir(["foo", "bar"])
    Dir.mktmpdir("foo", Dir.tmpdir, max_try: 3)
    Dir.mktmpdir(nil, nil, max_try: nil)

    Dir.mktmpdir() {}
    Dir.mktmpdir(["foo", "bar"]) {}
    Dir.mktmpdir("foo", Dir.tmpdir, max_try: 3) {}
    Dir.mktmpdir(nil, nil, max_try: nil) {}
  end
end
