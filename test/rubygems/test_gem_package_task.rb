# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems'

begin
  require 'rubygems/package_task'
rescue LoadError => e
  raise unless e.path == 'rake/packagetask'
end

unless defined?(Rake::PackageTask)
  warn 'Skipping Gem::PackageTask tests.  rake not found.'
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
      g.summary = 'summary'
    end

    Rake.application = Rake::Application.new

    pkg = Gem::PackageTask.new(gem) do |p|
      p.package_files << "y"
    end

    assert_equal %w[x y], pkg.package_files

    Dir.chdir @tempdir do
      FileUtils.touch 'x'
      FileUtils.touch 'y'

      Rake.application['package'].invoke

      assert_path_exists 'pkg/pkgr-1.2.3.gem'
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
      g.summary = 'summary'
    end

    _, err = capture_io do
      Rake.application = Rake::Application.new

      pkg = Gem::PackageTask.new(gem) do |p|
        p.package_files << "y"
      end

      assert_equal %w[x y], pkg.package_files

      Dir.chdir @tempdir do
        FileUtils.touch 'x'
        FileUtils.touch 'y'

        Rake.application['package'].invoke
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
      g.name = 'nokogiri'
      g.version = '1.5.0'
      g.platform = 'java'
    end

    pkg = Gem::PackageTask.new gem
    pkg.define

    assert_equal 'pkg/nokogiri-1.5.0-java', pkg.package_dir_path
  end
end if defined?(Rake::PackageTask)
