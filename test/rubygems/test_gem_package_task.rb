require 'rubygems/test_case'
require 'rubygems'
require 'rubygems/package_task'

class TestGemPackageTask < Gem::TestCase

  def setup
    super

    Rake.application = Rake::Application.new
    RakeFileUtils.verbose_flag = false
  end

  def test_gem_package
    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"

      g.authors = %w[author]
      g.files = %w[x]
      g.summary = 'summary'
    end

    pkg = Gem::PackageTask.new(gem)  do |p|
      p.package_files << "y"
    end

    assert_equal %w[x y], pkg.package_files

    Dir.chdir @tempdir do
      FileUtils.touch 'x'
      FileUtils.touch 'y'

      Rake.application['package'].invoke

      assert_path_exists 'pkg/pkgr-1.2.3.gem'
    end
  end

  def test_gem_package_with_current_platform
    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.files = Rake::FileList["x"].resolve
      g.platform = Gem::Platform::CURRENT
    end
    pkg = Gem::PackageTask.new(gem)  do |p|
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
    pkg = Gem::PackageTask.new(gem)  do |p|
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

end

