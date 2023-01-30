# frozen_string_literal: true
require_relative "helper"
require "rubygems/util"

class TestGemUtil < Gem::TestCase
  def test_class_popen
    pend "popen with a block does not behave well on jruby" if Gem.java_platform?
    assert_equal "0\n", Gem::Util.popen(*ruby_with_rubygems_in_load_path, "-e", "p 0")

    assert_raise Errno::ECHILD do
      Process.wait(-1)
    end
  end

  def test_silent_system
    pend if Gem.java_platform?
    Gem::Deprecate.skip_during do
      out, err = capture_output do
        Gem::Util.silent_system(*ruby_with_rubygems_in_load_path, "-e", 'puts "hello"; warn "hello"')
      end
      assert_empty out
      assert_empty err
    end
  end

  def test_traverse_parents
    FileUtils.mkdir_p "a/b/c"

    enum = Gem::Util.traverse_parents "a/b/c"

    assert_equal File.join(@tempdir, "a/b/c"), enum.next
    assert_equal File.join(@tempdir, "a/b"),   enum.next
    assert_equal File.join(@tempdir, "a"),     enum.next
    loop { break if enum.next.nil? } # exhaust the enumerator
  end

  def test_traverse_parents_does_not_crash_on_permissions_error
    pend "skipped on MS Windows (chmod has no effect)" if win_platform? || java_platform?

    FileUtils.mkdir_p "d/e/f"
    # remove 'execute' permission from "e" directory and make it
    # impossible to cd into it and its children
    FileUtils.chmod(0666, "d/e")

    pend "skipped in root privilege" if Process.uid.zero?

    paths = Gem::Util.traverse_parents("d/e/f").to_a

    assert_equal File.join(@tempdir, "d"), paths[0]
    assert_equal @tempdir, paths[1]
    assert_equal File.realpath("..", @tempdir), paths[2]
    assert_equal File.realpath("../..", @tempdir), paths[3]
  ensure
    # restore default permissions, allow the directory to be removed
    FileUtils.chmod(0775, "d/e") unless win_platform? || java_platform?
  end

  def test_glob_files_in_dir
    FileUtils.mkdir_p "g"
    FileUtils.touch File.join("g", "h.rb")
    FileUtils.touch File.join("g", "i.rb")

    expected_paths = [
      File.join(@tempdir, "g/h.rb"),
      File.join(@tempdir, "g/i.rb"),
    ]

    files_with_absolute_base = Gem::Util.glob_files_in_dir("*.rb", File.join(@tempdir, "g"))
    assert_equal expected_paths.sort, files_with_absolute_base.sort

    files_with_relative_base = Gem::Util.glob_files_in_dir("*.rb", "g")
    assert_equal expected_paths.sort, files_with_relative_base.sort
  end

  def test_correct_for_windows_path
    path = "/C:/WINDOWS/Temp/gems"
    assert_equal "C:/WINDOWS/Temp/gems", Gem::Util.correct_for_windows_path(path)

    path = "/home/skillet"
    assert_equal "/home/skillet", Gem::Util.correct_for_windows_path(path)
  end
end
