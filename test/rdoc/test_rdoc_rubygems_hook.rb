require 'rubygems'
require 'rubygems/test_case'
require 'rdoc/rubygems_hook'

class TestRDocRubygemsHook < Gem::TestCase

  def setup
    super

    skip 'requires RubyGems 1.9+' unless
      Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.9')

    @a = util_spec 'a' do |s|
      s.rdoc_options = %w[--main MyTitle]
      s.extra_rdoc_files = %w[README]
    end

    write_file File.join(@tempdir, 'lib', 'a.rb')
    write_file File.join(@tempdir, 'README')

    install_gem @a

    @hook = RDoc::RubygemsHook.new @a

    begin
      RDoc::RubygemsHook.load_rdoc
    rescue Gem::DocumentError => e
      skip e.message
    end

    Gem.configuration[:rdoc] = nil
  end

  def test_initialize
    refute @hook.generate_rdoc
    assert @hook.generate_ri

    rdoc = RDoc::RubygemsHook.new @a, false, false

    refute rdoc.generate_rdoc
    refute rdoc.generate_ri
  end

  def test_delete_legacy_args
    args = %w[
      --inline-source
      --one-file
      --promiscuous
      -p
    ]

    @hook.delete_legacy_args args

    assert_empty args
  end

  def test_document
    options = RDoc::Options.new
    options.files = []

    rdoc = @hook.new_rdoc
    rdoc.store = RDoc::Store.new
    @hook.instance_variable_set :@rdoc, rdoc
    @hook.instance_variable_set :@file_info, []

    @hook.document 'darkfish', options, @a.doc_dir('rdoc')

    assert @hook.rdoc_installed?
  end

  def test_generate
    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate

    refute @hook.rdoc_installed?
    assert @hook.ri_installed?

    rdoc = @hook.instance_variable_get :@rdoc

    refute rdoc.options.hyperlink_all
    assert_equal Pathname(@a.full_gem_path), rdoc.options.root
    assert_equal %w[README lib], rdoc.options.files.sort

    assert_equal 'MyTitle', rdoc.store.main
  end

  def test_generate_all
    @hook.generate_rdoc = true
    @hook.generate_ri   = true

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate

    assert @hook.rdoc_installed?
    assert @hook.ri_installed?

    rdoc = @hook.instance_variable_get :@rdoc

    refute rdoc.options.hyperlink_all
    assert_equal Pathname(@a.full_gem_path), rdoc.options.root
    assert_equal %w[README lib], rdoc.options.files.sort

    assert_equal 'MyTitle', rdoc.store.main
  end

  def test_generate_configuration_rdoc_array
    Gem.configuration[:rdoc] = %w[-A]

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate

    rdoc = @hook.instance_variable_get :@rdoc

    assert rdoc.options.hyperlink_all
  end

  def test_generate_configuration_rdoc_string
    Gem.configuration[:rdoc] = '-A'

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate

    rdoc = @hook.instance_variable_get :@rdoc

    assert rdoc.options.hyperlink_all
  end

  def test_generate_default_gem
    skip 'RubyGems 2 required' unless @a.respond_to? :default_gem?
    @a.loaded_from =
      File.join Gem::Specification.default_specifications_dir, 'a.gemspec'

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate

    refute @hook.rdoc_installed?
    refute @hook.ri_installed?
  end

  def test_generate_disabled
    @hook.generate_rdoc = false
    @hook.generate_ri   = false

    @hook.generate

    refute @hook.rdoc_installed?
    refute @hook.ri_installed?
  end

  def test_generate_force
    FileUtils.mkdir_p @a.doc_dir 'ri'
    FileUtils.mkdir_p @a.doc_dir 'rdoc'
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.force = true

    @hook.generate

    refute_path_exists File.join(@a.doc_dir('rdoc'), 'index.html')
    assert_path_exists File.join(@a.doc_dir('ri'),   'cache.ri')
  end

  def test_generate_no_overwrite
    FileUtils.mkdir_p @a.doc_dir 'ri'
    FileUtils.mkdir_p @a.doc_dir 'rdoc'
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate

    refute_path_exists File.join(@a.doc_dir('rdoc'), 'index.html')
    refute_path_exists File.join(@a.doc_dir('ri'),   'cache.ri')
  end

  def test_new_rdoc
    assert_kind_of RDoc::RDoc, @hook.new_rdoc
  end

  def test_rdoc_installed?
    refute @hook.rdoc_installed?

    FileUtils.mkdir_p @a.doc_dir 'rdoc'

    assert @hook.rdoc_installed?
  end

  def test_remove
    FileUtils.mkdir_p @a.doc_dir 'rdoc'
    FileUtils.mkdir_p @a.doc_dir 'ri'

    @hook.remove

    refute @hook.rdoc_installed?
    refute @hook.ri_installed?

    assert_path_exists @a.doc_dir
  end

  def test_remove_unwritable
    skip 'chmod not supported' if Gem.win_platform?
    FileUtils.mkdir_p @a.base_dir
    FileUtils.chmod 0, @a.base_dir

    e = assert_raises Gem::FilePermissionError do
      @hook.remove
    end

    assert_equal @a.base_dir, e.directory
  ensure
    FileUtils.chmod(0755, @a.base_dir) if File.directory?(@a.base_dir)
  end

  def test_ri_installed?
    refute @hook.ri_installed?

    FileUtils.mkdir_p @a.doc_dir 'ri'

    assert @hook.ri_installed?
  end

  def test_setup
    @hook.setup

    assert_path_exists @a.doc_dir
  end

  def test_setup_unwritable
    skip 'chmod not supported' if Gem.win_platform?
    FileUtils.mkdir_p @a.doc_dir
    FileUtils.chmod 0, @a.doc_dir

    e = assert_raises Gem::FilePermissionError do
      @hook.setup
    end

    assert_equal @a.doc_dir, e.directory
  ensure
    if File.exist? @a.doc_dir
      FileUtils.chmod 0755, @a.doc_dir
      FileUtils.rm_r @a.doc_dir
    end
  end

end

