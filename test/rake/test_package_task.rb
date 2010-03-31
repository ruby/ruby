require 'tmpdir'
require 'fileutils'
require 'test/unit'
require 'rake/packagetask'

class Rake::TestPackageTask < Test::Unit::TestCase
  include Rake

  def test_create
    pwd = Dir.pwd
    tmpdir = Dir.mktmpdir("rake")
    Dir.chdir(tmpdir)
    Dir.mkdir("bin")
    open("bin/rake", "wb") {}
    pkg = Rake::PackageTask.new("pkgr", "1.2.3") { |p|
      p.package_files << "install.rb"
      p.package_files.include(
        '[A-Z]*',
        'bin/**/*',
        'lib/**/*.rb',
        'test/**/*.rb',
        'doc/**/*',
        'build/rubyapp.rb',
        '*.blurb')
      p.package_files.exclude(/\bCVS\b/)
      p.package_files.exclude(/~$/)
      p.package_dir = 'pkg'
      p.need_tar = true
      p.need_tar_gz = true
      p.need_tar_bz2 = true
      p.need_zip = true
    }
    assert_equal "pkg", pkg.package_dir
    assert pkg.package_files.include?("bin/rake")
    assert "pkgr", pkg.name
    assert "1.2.3", pkg.version
    assert Task[:package]
    assert Task['pkg/pkgr-1.2.3.tgz']
    assert Task['pkg/pkgr-1.2.3.tar.gz']
    assert Task['pkg/pkgr-1.2.3.tar.bz2']
    assert Task['pkg/pkgr-1.2.3.zip']
    assert Task["pkg/pkgr-1.2.3"]
    assert Task[:clobber_package]
    assert Task[:repackage]
  ensure
    Dir.chdir(pwd)
    FileUtils.rm_rf(tmpdir)
  end

  def test_missing_version
    assert_raise(RuntimeError) {
      pkg = Rake::PackageTask.new("pkgr") { |p| }
    }
  end

  def test_no_version
    pkg = Rake::PackageTask.new("pkgr", :noversion) { |p| }
    assert "pkgr", pkg.send(:package_name)
  end

  def test_clone
    pkg = Rake::PackageTask.new("x", :noversion)
    p2 = pkg.clone
    pkg.package_files << "y"
    p2.package_files << "x"
    assert_equal ["y"], pkg.package_files
    assert_equal ["x"], p2.package_files
  end
end


require 'rake/gempackagetask'

class Rake::TestGemPackageTask < Test::Unit::TestCase
  def test_gem_package
    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.files = FileList["x"].resolve
    end
    pkg = Rake::GemPackageTask.new(gem)  do |p|
      p.package_files << "y"
    end
    assert_equal ["x", "y"], pkg.package_files
    assert_equal "pkgr-1.2.3.gem", pkg.gem_file
  end

  def test_gem_package_with_current_platform
    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.files = FileList["x"].resolve
      g.platform = Gem::Platform::CURRENT
    end
    pkg = Rake::GemPackageTask.new(gem)  do |p|
      p.package_files << "y"
    end
    assert_equal ["x", "y"], pkg.package_files
    assert_match(/^pkgr-1\.2\.3-(\S+)\.gem$/, pkg.gem_file)
  end

  def test_gem_package_with_ruby_platform
    gem = Gem::Specification.new do |g|
      g.name = "pkgr"
      g.version = "1.2.3"
      g.files = FileList["x"].resolve
      g.platform = Gem::Platform::RUBY
    end
    pkg = Rake::GemPackageTask.new(gem)  do |p|
      p.package_files << "y"
    end
    assert_equal ["x", "y"], pkg.package_files
    assert_equal "pkgr-1.2.3.gem", pkg.gem_file
  end
end
