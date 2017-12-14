require File.expand_path('../helper', __FILE__)
require 'rake/clean'

class TestRakeClean < Rake::TestCase
  def test_clean
    load 'rake/clean.rb', true

    assert Rake::Task['clean'], "Should define clean"
    assert Rake::Task['clobber'], "Should define clobber"
    assert Rake::Task['clobber'].prerequisites.include?("clean"),
      "Clobber should require clean"
  end

  def test_cleanup
    file_name = create_undeletable_file

    out, _ = capture_io do
      Rake::Cleaner.cleanup(file_name, :verbose => false)
    end
    assert_match(/failed to remove/i, out)

  ensure
    remove_undeletable_file
  end

  def test_cleanup_ignores_missing_files
    file_name = File.join(@tempdir, "missing_directory", "no_such_file")

    out, _ = capture_io do
      Rake::Cleaner.cleanup(file_name, :verbose => false)
    end
    refute_match(/failed to remove/i, out)
  end

  private

  def create_undeletable_file
    dir_name = File.join(@tempdir, "deletedir")
    file_name = File.join(dir_name, "deleteme")
    FileUtils.mkdir(dir_name)
    FileUtils.touch(file_name)
    FileUtils.chmod(0, file_name)
    FileUtils.chmod(0, dir_name)
    begin
      FileUtils.chmod(0644, file_name)
    rescue
      file_name
    else
      skip "Permission to delete files is different on thie system"
    end
  end

  def remove_undeletable_file
    dir_name = File.join(@tempdir, "deletedir")
    file_name = File.join(dir_name, "deleteme")
    FileUtils.chmod(0777, dir_name)
    FileUtils.chmod(0777, file_name)
    Rake::Cleaner.cleanup(file_name, :verbose => false)
    Rake::Cleaner.cleanup(dir_name, :verbose => false)
  end
end
