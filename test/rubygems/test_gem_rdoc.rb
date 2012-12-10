require 'rubygems/test_case'
require 'rubygems'
require 'rubygems/rdoc'

class TestGemRDoc < Gem::TestCase
  Gem::RDoc.load_rdoc
  rdoc_4 = Gem::Requirement.new('> 3').satisfied_by?(Gem::RDoc.rdoc_version)

  def setup
    super

    @a = quick_spec 'a'

    @rdoc = Gem::RDoc.new @a

    begin
      Gem::RDoc.load_rdoc
    rescue Gem::DocumentError => e
      skip e.message
    end

    Gem.configuration[:rdoc] = nil
  end

  ##
  # RDoc 4 ships with its own Gem::RDoc which overrides this one which is
  # shipped for backwards compatibility.

  def rdoc_3?
    Gem::Requirement.new('~> 3.0').satisfied_by? @rdoc.class.rdoc_version
  end

  def rdoc_3_8_or_better?
    Gem::Requirement.new('>= 3.8').satisfied_by? @rdoc.class.rdoc_version
  end

  def test_initialize
    assert @rdoc.generate_rdoc
    assert @rdoc.generate_ri

    rdoc = Gem::RDoc.new @a, false, false

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

    @rdoc.delete_legacy_args args

    assert_empty args
  end

  def test_document
    skip 'RDoc 3 required' unless rdoc_3?

    options = RDoc::Options.new
    options.files = []

    @rdoc.instance_variable_set :@rdoc, @rdoc.new_rdoc
    @rdoc.instance_variable_set :@file_info, []

    @rdoc.document 'darkfish', options, @a.doc_dir('rdoc')

    assert @rdoc.rdoc_installed?
  end unless rdoc_4

  def test_generate
    skip 'RDoc 3 required' unless rdoc_3?

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @rdoc.generate

    assert @rdoc.rdoc_installed?
    assert @rdoc.ri_installed?

    rdoc = @rdoc.instance_variable_get :@rdoc

    refute rdoc.options.hyperlink_all
  end unless rdoc_4

  def test_generate_configuration_rdoc_array
    skip 'RDoc 3 required' unless rdoc_3?

    Gem.configuration[:rdoc] = %w[-A]

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @rdoc.generate

    rdoc = @rdoc.instance_variable_get :@rdoc

    assert rdoc.options.hyperlink_all
  end unless rdoc_4

  def test_generate_configuration_rdoc_string
    skip 'RDoc 3 required' unless rdoc_3?

    Gem.configuration[:rdoc] = '-A'

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @rdoc.generate

    rdoc = @rdoc.instance_variable_get :@rdoc

    assert rdoc.options.hyperlink_all
  end unless rdoc_4

  def test_generate_disabled
    @rdoc.generate_rdoc = false
    @rdoc.generate_ri   = false

    @rdoc.generate

    refute @rdoc.rdoc_installed?
    refute @rdoc.ri_installed?
  end

  def test_generate_force
    skip 'RDoc 3 required' unless rdoc_3?

    FileUtils.mkdir_p @a.doc_dir 'ri'
    FileUtils.mkdir_p @a.doc_dir 'rdoc'
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @rdoc.force = true

    @rdoc.generate

    assert_path_exists File.join(@a.doc_dir('rdoc'), 'index.html')
    assert_path_exists File.join(@a.doc_dir('ri'),   'cache.ri')
  end unless rdoc_4

  def test_generate_no_overwrite
    skip 'RDoc 3 required' unless rdoc_3?

    FileUtils.mkdir_p @a.doc_dir 'ri'
    FileUtils.mkdir_p @a.doc_dir 'rdoc'
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @rdoc.generate

    refute_path_exists File.join(@a.doc_dir('rdoc'), 'index.html')
    refute_path_exists File.join(@a.doc_dir('ri'),   'cache.ri')
  end unless rdoc_4

  def test_generate_legacy
    skip 'RDoc < 3.8 required' if rdoc_3_8_or_better?

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @rdoc.generate_legacy

    assert @rdoc.rdoc_installed?
    assert @rdoc.ri_installed?
  end unless rdoc_4

  def test_legacy_rdoc
    skip 'RDoc < 3.8 required' if rdoc_3_8_or_better?

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @rdoc.legacy_rdoc '--op', @a.doc_dir('rdoc')

    assert @rdoc.rdoc_installed?
  end unless rdoc_4

  def test_new_rdoc
    assert_kind_of RDoc::RDoc, @rdoc.new_rdoc
  end

  def test_rdoc_installed?
    refute @rdoc.rdoc_installed?

    FileUtils.mkdir_p @a.doc_dir 'rdoc'

    assert @rdoc.rdoc_installed?
  end

  def test_remove
    FileUtils.mkdir_p @a.doc_dir 'rdoc'
    FileUtils.mkdir_p @a.doc_dir 'ri'

    @rdoc.remove

    refute @rdoc.rdoc_installed?
    refute @rdoc.ri_installed?

    assert_path_exists @a.doc_dir
  end

  def test_remove_unwritable
    skip 'chmod not supported' if Gem.win_platform?
    FileUtils.mkdir_p @a.base_dir
    FileUtils.chmod 0, @a.base_dir

    e = assert_raises Gem::FilePermissionError do
      @rdoc.remove
    end

    assert_equal @a.base_dir, e.directory
  ensure
    FileUtils.chmod(0755, @a.base_dir) if File.directory?(@a.base_dir)
  end

  def test_ri_installed?
    refute @rdoc.ri_installed?

    FileUtils.mkdir_p @a.doc_dir 'ri'

    assert @rdoc.ri_installed?
  end

  def test_setup
    @rdoc.setup

    assert_path_exists @a.doc_dir
  end

  def test_setup_unwritable
    skip 'chmod not supported' if Gem.win_platform?
    FileUtils.mkdir_p @a.doc_dir
    FileUtils.chmod 0, @a.doc_dir

    e = assert_raises Gem::FilePermissionError do
      @rdoc.setup
    end

    assert_equal @a.doc_dir, e.directory
  ensure
    FileUtils.chmod(0755, @a.doc_dir) if File.directory?(@a.doc_dir)
  end

end
