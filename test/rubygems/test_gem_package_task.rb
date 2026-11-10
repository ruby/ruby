# frozen_string_literal: true

require_relative "helper"
require "rubygems"

begin
  require "rubygems/package_task"
rescue LoadError => e
  raise unless e.path == "rake/packagetask"
end

class TestGemPackageTask < Gem::TestCase
  def test_gem_package
    original_rake_fileutils_verbosity = RakeFileUtils.verbose_flag
    RakeFileUtils.verbose_flag = false

    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"

      g.authors = %w[author]
      g.files = %w[x]
      g.summary = "summary"
    end

    Rake.application = Rake::Application.new

    pkg = Gem::PackageTask.new(gem) do |p|
      p.package_files << "y"
    end

    assert_equal %w[x y], pkg.package_files

    Dir.chdir @tempdir do
      FileUtils.touch "x"
      FileUtils.touch "y"

      Rake.application["package"].invoke

      assert_path_exist "pkg/pkgr-1.2.3.gem"
      assert_path_not_exist "pkg/pkgr-1.2.3.gem-built"
      assert_equal %w[x y], Dir.children("pkg/pkgr-1.2.3").sort
    end
  ensure
    RakeFileUtils.verbose_flag = original_rake_fileutils_verbosity
  end

  def test_builds_content_addressable_gem_and_records_it_in_the_stamp_file
    original_rake_fileutils_verbosity = RakeFileUtils.verbose_flag
    RakeFileUtils.verbose_flag = false

    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.platform = "arm64-darwin"
      g.required_ruby_version = "~> 3.4.0"

      g.authors = %w[author]
      g.files = %w[x]
      g.summary = "summary"
    end

    Dir.chdir @tempdir do
      FileUtils.touch "x"
      FileUtils.touch "y"

      Rake.application = Rake::Application.new

      pkg = Gem::PackageTask.new(gem) do |p|
        p.package_files << "y"
        p.content_addressable = true
      end

      assert_equal %w[x y], pkg.package_files

      Rake.application["package"].invoke

      built_files = Dir["pkg/pkgr-1.2.3-*.gem"]
      assert_equal 1, built_files.length

      built_gem_path = built_files.first
      assert_match(%r{\Apkg/pkgr-1\.2\.3-[0-9a-f]{8}\.gem\z}, built_gem_path)
      assert_path_not_exist "pkg/pkgr-1.2.3-arm64-darwin.gem"

      stamp_path = "pkg/pkgr-1.2.3-arm64-darwin-3.4.gem-built"
      assert_path_exist stamp_path
      assert_equal built_gem_path, File.read(stamp_path)

      assert_equal %w[x y], Dir.children("pkg/pkgr-1.2.3-arm64-darwin-3.4").sort
      assert_path_not_exist "pkg/pkgr-1.2.3-arm64-darwin"

      built_spec = Gem::Package.new(built_gem_path).spec
      assert_equal "3.4", built_spec.ruby_abi
      assert_equal Gem::Requirement.new("~> 3.4.0"), built_spec.required_ruby_version
    end
  ensure
    RakeFileUtils.verbose_flag = original_rake_fileutils_verbosity
  end

  def test_rebuilds_content_addressable_gem_when_stamp_points_to_missing_gem
    original_rake_fileutils_verbosity = RakeFileUtils.verbose_flag
    RakeFileUtils.verbose_flag = false

    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.platform = "arm64-darwin"
      g.required_ruby_version = "~> 3.4.0"

      g.authors = %w[author]
      g.files = %w[x]
      g.summary = "summary"
    end

    Dir.chdir @tempdir do
      FileUtils.touch "x"
      FileUtils.mkdir_p "pkg"

      stamp_path = "pkg/pkgr-1.2.3-arm64-darwin-3.4.gem-built"
      missing_gem_path = "pkg/pkgr-1.2.3-deadbeef.gem"
      File.write stamp_path, missing_gem_path

      Rake.application = Rake::Application.new
      Gem::PackageTask.new(gem) do |package|
        package.content_addressable = true
      end

      assert_path_not_exist stamp_path

      Rake.application["package"].invoke

      built_files = Dir["pkg/pkgr-1.2.3-*.gem"]
      assert_equal 1, built_files.length

      built_gem_path = built_files.first
      assert_match(%r{\Apkg/pkgr-1\.2\.3-[0-9a-f]{8}\.gem\z}, built_gem_path)
      assert_path_exist stamp_path
      assert_equal built_gem_path, File.read(stamp_path)
    end
  ensure
    RakeFileUtils.verbose_flag = original_rake_fileutils_verbosity
  end

  def test_discards_empty_content_addressable_stamp_file
    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.platform = "arm64-darwin"
      g.required_ruby_version = "~> 3.4.0"

      g.authors = %w[author]
      g.files = %w[x]
      g.summary = "summary"
    end

    Dir.chdir @tempdir do
      FileUtils.touch "x"
      FileUtils.mkdir_p "pkg"

      stamp_path = "pkg/pkgr-1.2.3-arm64-darwin-3.4.gem-built"
      FileUtils.touch stamp_path

      out, err = capture_output do
        Rake.application = Rake::Application.new
        Gem::PackageTask.new(gem) do |package|
          package.content_addressable = true
        end
      end

      assert_path_not_exist stamp_path
      assert_empty out
      assert_empty err
    end
  end

  def test_does_not_rebuild_content_addressable_gem_when_stamp_is_up_to_date
    original_rake_fileutils_verbosity = RakeFileUtils.verbose_flag
    RakeFileUtils.verbose_flag = false

    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.platform = "arm64-darwin"
      g.required_ruby_version = "~> 3.4.0"

      g.authors = %w[author]
      g.files = %w[x]
      g.summary = "summary"
    end

    Dir.chdir @tempdir do
      FileUtils.touch "x"

      Rake.application = Rake::Application.new
      Gem::PackageTask.new(gem) do |package|
        package.content_addressable = true
      end
      Rake.application["package"].invoke

      built_files = Dir["pkg/pkgr-1.2.3-*.gem"]
      assert_equal 1, built_files.length

      Rake.application = Rake::Application.new
      Gem::PackageTask.new(gem) do |package|
        package.content_addressable = true
      end

      Gem::Package.stub :build, ->(*) { flunk "expected the gem not to be rebuilt" } do
        Rake.application["package"].invoke
      end

      assert_equal built_files, Dir["pkg/pkgr-1.2.3-*.gem"]
      assert_equal built_files.first, File.read("pkg/pkgr-1.2.3-arm64-darwin-3.4.gem-built")
    end
  ensure
    RakeFileUtils.verbose_flag = original_rake_fileutils_verbosity
  end

  def test_rebuilds_content_addressable_gem_and_removes_previous_build_when_files_change
    original_rake_fileutils_verbosity = RakeFileUtils.verbose_flag
    RakeFileUtils.verbose_flag = false

    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.platform = "arm64-darwin"
      g.required_ruby_version = "~> 3.4.0"

      g.authors = %w[author]
      g.files = %w[x]
      g.summary = "summary"
    end

    Dir.chdir @tempdir do
      stamp_path = "pkg/pkgr-1.2.3-arm64-darwin-3.4.gem-built"

      FileUtils.touch "x"

      Rake.application = Rake::Application.new
      Gem::PackageTask.new(gem) do |package|
        package.content_addressable = true
      end
      Rake.application["package"].invoke

      first_gem_path = File.read(stamp_path)
      assert_path_exist first_gem_path

      File.write "x", "changed"
      newer = File.mtime(stamp_path) + 10
      File.utime newer, newer, "x"

      Rake.application = Rake::Application.new
      Gem::PackageTask.new(gem) do |package|
        package.content_addressable = true
      end
      Rake.application["package"].invoke

      second_gem_path = File.read(stamp_path)
      refute_equal first_gem_path, second_gem_path

      assert_path_not_exist first_gem_path
      assert_path_exist second_gem_path
      assert_equal [second_gem_path], Dir["pkg/pkgr-1.2.3-*.gem"]
    end
  ensure
    RakeFileUtils.verbose_flag = original_rake_fileutils_verbosity
  end

  def test_keeps_previous_content_addressable_gem_when_rebuild_fails
    original_rake_fileutils_verbosity = RakeFileUtils.verbose_flag
    RakeFileUtils.verbose_flag = false

    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.platform = "arm64-darwin"
      g.required_ruby_version = "~> 3.4.0"

      g.authors = %w[author]
      g.files = %w[x]
      g.summary = "summary"
    end

    Dir.chdir @tempdir do
      stamp_path = "pkg/pkgr-1.2.3-arm64-darwin-3.4.gem-built"

      FileUtils.touch "x"

      Rake.application = Rake::Application.new
      Gem::PackageTask.new(gem) do |package|
        package.content_addressable = true
      end
      Rake.application["package"].invoke

      first_gem_path = File.read(stamp_path)
      assert_path_exist first_gem_path

      File.write "x", "changed"
      newer = File.mtime(stamp_path) + 10
      File.utime newer, newer, "x"

      Rake.application = Rake::Application.new
      Gem::PackageTask.new(gem) do |package|
        package.content_addressable = true
      end

      Gem::Package.stub :build, ->(*) { raise Gem::InvalidSpecificationException, "boom" } do
        assert_raise(Gem::InvalidSpecificationException) do
          Rake.application["package"].invoke
        end
      end

      assert_path_exist first_gem_path
      assert_equal first_gem_path, File.read(stamp_path)
      assert_equal [first_gem_path], Dir["pkg/pkgr-1.2.3-*.gem"]
    end
  ensure
    RakeFileUtils.verbose_flag = original_rake_fileutils_verbosity
  end

  def test_keeps_content_addressable_gem_when_rebuild_produces_same_content
    original_rake_fileutils_verbosity = RakeFileUtils.verbose_flag
    RakeFileUtils.verbose_flag = false

    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.platform = "arm64-darwin"
      g.required_ruby_version = "~> 3.4.0"

      g.authors = %w[author]
      g.files = %w[x]
      g.summary = "summary"
    end

    Dir.chdir @tempdir do
      stamp_path = "pkg/pkgr-1.2.3-arm64-darwin-3.4.gem-built"

      FileUtils.touch "x"

      Rake.application = Rake::Application.new
      Gem::PackageTask.new(gem) do |package|
        package.content_addressable = true
      end
      Rake.application["package"].invoke

      first_gem_path = File.read(stamp_path)

      newer = File.mtime(stamp_path) + 10
      File.utime newer, newer, "x"

      Rake.application = Rake::Application.new
      Gem::PackageTask.new(gem) do |package|
        package.content_addressable = true
      end
      Rake.application["package"].invoke

      assert_equal first_gem_path, File.read(stamp_path)
      assert_path_exist first_gem_path
      assert_equal [first_gem_path], Dir["pkg/pkgr-1.2.3-*.gem"]
    end
  ensure
    RakeFileUtils.verbose_flag = original_rake_fileutils_verbosity
  end

  def test_gem_package_prints_to_stdout_by_default
    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"

      g.authors = %w[author]
      g.files = %w[x]
      g.summary = "summary"
    end

    _, err = capture_output do
      Rake.application = Rake::Application.new

      pkg = Gem::PackageTask.new(gem) do |p|
        p.package_files << "y"
      end

      assert_equal %w[x y], pkg.package_files

      Dir.chdir @tempdir do
        FileUtils.touch "x"
        FileUtils.touch "y"

        Rake.application["package"].invoke
      end
    end

    assert_empty err
  end

  def test_gem_package_with_current_platform
    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.files = Rake::FileList["x"].resolve
      g.platform = Gem::Platform::CURRENT
    end
    pkg = Gem::PackageTask.new(gem) do |p|
      p.package_files << "y"
    end
    assert_equal ["x", "y"], pkg.package_files
  end

  def test_gem_package_with_ruby_platform
    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.files = Rake::FileList["x"].resolve
      g.platform = Gem::Platform::RUBY
    end
    pkg = Gem::PackageTask.new(gem) do |p|
      p.package_files << "y"
    end
    assert_equal ["x", "y"], pkg.package_files
  end

  def test_package_dir_path
    gem = Gem::Specification.new do |g|
      g.name = "nokogiri"
      g.version = "1.5.0"
      g.platform = "java"
    end

    pkg = Gem::PackageTask.new gem
    pkg.define

    assert_equal "pkg/nokogiri-1.5.0-java", pkg.package_dir_path
  end

  def test_package_dir_path_with_content_addressable
    gem = Gem::Specification.new do |g|
      g.name = "nokogiri"
      g.version = "1.5.0"
      g.platform = "x86_64-linux"
      g.required_ruby_version = "~> 3.4.0"
    end

    pkg = Gem::PackageTask.new gem
    pkg.content_addressable = true
    pkg.define

    assert_equal "nokogiri-1.5.0-x86_64-linux-3.4", pkg.package_name
    assert_equal "pkg/nokogiri-1.5.0-x86_64-linux-3.4", pkg.package_dir_path
    assert_equal "nokogiri-1.5.0-x86_64-linux-3.4.tgz", pkg.tgz_file
  end

  def test_content_addressable_package_with_need_tar
    original_rake_fileutils_verbosity = RakeFileUtils.verbose_flag
    RakeFileUtils.verbose_flag = false

    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.platform = "arm64-darwin"
      g.required_ruby_version = "~> 3.4.0"

      g.authors = %w[author]
      g.files = %w[x]
      g.summary = "summary"
    end

    Dir.chdir @tempdir do
      FileUtils.touch "x"

      Rake.application = Rake::Application.new

      Gem::PackageTask.new(gem) do |p|
        p.content_addressable = true
        p.need_tar = true
      end

      Rake.application["package"].invoke

      built_files = Dir["pkg/pkgr-1.2.3-*.gem"]
      assert_equal 1, built_files.length
      assert_equal built_files.first, File.read("pkg/pkgr-1.2.3-arm64-darwin-3.4.gem-built")
      assert_path_exist "pkg/pkgr-1.2.3-arm64-darwin-3.4.tgz"
    end
  ensure
    RakeFileUtils.verbose_flag = original_rake_fileutils_verbosity
  end

  def test_content_addressable_raises_when_required_ruby_version_does_not_identify_single_abi
    gem = Gem::Specification.new do |g|
      g.name = "nokogiri"
      g.version = "1.5.0"
      g.platform = "x86_64-linux"
      g.required_ruby_version = ">= 3.4"
    end

    Rake.application = Rake::Application.new

    pkg = Gem::PackageTask.new gem
    pkg.content_addressable = true

    error = assert_raise(ArgumentError) { pkg.define }
    assert_match(/required_ruby_version is set to >= 3.4/, error.message)
    assert_match(/identifies a single Ruby ABI/, error.message)
    assert_empty Rake.application.tasks
  end

  def test_content_addressable_raises_when_platform_is_ruby
    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.required_ruby_version = "~> 3.4.0"
    end

    Rake.application = Rake::Application.new

    pkg = Gem::PackageTask.new gem
    pkg.content_addressable = true

    error = assert_raise(ArgumentError) { pkg.define }
    assert_match(/no platform or a Ruby platform has been set/, error.message)
    assert_empty Rake.application.tasks
  end
end if defined?(Rake::PackageTask)
