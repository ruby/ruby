# frozen_string_literal: true
require_relative 'helper'

class TestRDocRIPaths < RDoc::TestCase

  def setup
    super

    @orig_env = ENV.to_hash
    @orig_gem_path = Gem.path

    @tempdir = File.join Dir.tmpdir, "test_rdoc_ri_paths_#{$$}"
    Gem.use_paths @tempdir
    Gem.ensure_gem_subdirectories @tempdir

    specs = [
      @rake_10   = Gem::Specification.new('rake', '10.0.1'),
      @rdoc_4_0  = Gem::Specification.new('rdoc', '4.0'),
      @rdoc_3_12 = Gem::Specification.new('rdoc', '3.12'),
      @nodoc     = Gem::Specification.new('nodoc', '1.0'),
    ]

    specs.each do |spec|
      spec.loaded_from = spec.spec_file

      File.open spec.spec_file, 'w' do |file|
        file.write spec.to_ruby_for_cache
      end

      FileUtils.mkdir_p File.join(spec.doc_dir, 'ri') unless
        spec.name == 'nodoc'
    end

    Gem::Specification.reset
    Gem::Specification.all = specs
  end

  def teardown
    super

    Gem.use_paths(*@orig_gem_path)
    Gem::Specification.reset
    FileUtils.rm_rf @tempdir
    ENV.replace(@orig_env)
  end

  def test_class_each
    enum = RDoc::RI::Paths.each true, true, true, :all

    path = enum.map { |dir,| dir }

    assert_equal RDoc::RI::Paths.system_dir,          path.shift
    assert_equal RDoc::RI::Paths.site_dir,            path.shift
    assert_equal RDoc::RI::Paths.home_dir,            path.shift
    assert_equal File.join(@nodoc.doc_dir, 'ri'),     path.shift
    assert_equal File.join(@rake_10.doc_dir, 'ri'),   path.shift
    assert_equal File.join(@rdoc_4_0.doc_dir, 'ri'),  path.shift
    assert_equal File.join(@rdoc_3_12.doc_dir, 'ri'), path.shift
    assert_empty path
  end

  def test_class_gemdirs_latest
    Dir.chdir @tempdir do
      gemdirs = RDoc::RI::Paths.gemdirs :latest

      expected = [
        File.join(@rake_10.doc_dir, 'ri'),
        File.join(@rdoc_4_0.doc_dir, 'ri'),
      ]

      assert_equal expected, gemdirs
    end
  end

  def test_class_gemdirs_legacy
    Dir.chdir @tempdir do
      gemdirs = RDoc::RI::Paths.gemdirs true

      expected = [
        File.join(@rake_10.doc_dir, 'ri'),
        File.join(@rdoc_4_0.doc_dir, 'ri'),
      ]

      assert_equal expected, gemdirs
    end
  end

  def test_class_gemdirs_all
    Dir.chdir @tempdir do
      gemdirs = RDoc::RI::Paths.gemdirs :all

      expected = [
        File.join(@nodoc.doc_dir,     'ri'),
        File.join(@rake_10.doc_dir,   'ri'),
        File.join(@rdoc_4_0.doc_dir,  'ri'),
        File.join(@rdoc_3_12.doc_dir, 'ri'),
      ]

      assert_equal expected, gemdirs
    end
  end

  def test_class_gem_dir
    dir = RDoc::RI::Paths.gem_dir 'rake', '10.0.1'

    expected = File.join @rake_10.doc_dir, 'ri'

    assert_equal expected, dir
  end

  def test_class_home_dir
    dir = RDoc::RI::Paths.home_dir

    assert_equal RDoc::RI::Paths::HOMEDIR, dir
  end

  def test_class_path_nonexistent
    temp_dir do |dir|
      nonexistent = File.join dir, 'nonexistent'
      dir = RDoc::RI::Paths.path true, true, true, true, nonexistent

      refute_includes dir, nonexistent
    end
  end

  def test_class_raw_path
    path = RDoc::RI::Paths.raw_path true, true, true, true

    assert_equal RDoc::RI::Paths.system_dir,        path.shift
    assert_equal RDoc::RI::Paths.site_dir,          path.shift
    assert_equal RDoc::RI::Paths.home_dir,          path.shift
    assert_equal File.join(@rake_10.doc_dir, 'ri'), path.shift
  end

  def test_class_raw_path_extra_dirs
    path = RDoc::RI::Paths.raw_path true, true, true, true, '/nonexistent'

    assert_equal '/nonexistent',                    path.shift
    assert_equal RDoc::RI::Paths.system_dir,        path.shift
    assert_equal RDoc::RI::Paths.site_dir,          path.shift
    assert_equal RDoc::RI::Paths.home_dir,          path.shift
    assert_equal File.join(@rake_10.doc_dir, 'ri'), path.shift
  end

  def test_class_site_dir
    dir = RDoc::RI::Paths.site_dir

    assert_equal File.join(RDoc::RI::Paths::BASE, 'site'), dir
  end

  def test_class_system_dir
    dir = RDoc::RI::Paths.system_dir

    assert_equal File.join(RDoc::RI::Paths::BASE, 'system'), dir
  end

end

