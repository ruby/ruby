# frozen_string_literal: true
require 'rubygems'
require 'rubygems/test_case'
require 'rubygems/rdoc'

class TestGemRDoc < Gem::TestCase
  Gem::RDoc.load_rdoc
  rdoc_4 = Gem::Requirement.new('> 3').satisfied_by?(Gem::RDoc.rdoc_version)

  def setup
    super

    @a = util_spec 'a' do |s|
      s.rdoc_options = %w[--main MyTitle]
      s.extra_rdoc_files = %w[README]
    end

    write_file File.join(@tempdir, 'lib', 'a.rb')
    write_file File.join(@tempdir, 'README')

    install_gem @a

    @hook = Gem::RDoc.new @a

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

  def rdoc_4?
    Gem::Requirement.new('>= 4.0.0.preview2').satisfied_by? \
      @hook.class.rdoc_version
  end

  def rdoc_3?
    Gem::Requirement.new('~> 3.0').satisfied_by? @hook.class.rdoc_version
  end

  def rdoc_3_8_or_better?
    Gem::Requirement.new('>= 3.8').satisfied_by? @hook.class.rdoc_version
  end

  def test_initialize
    if rdoc_4?
      refute @hook.generate_rdoc
    else
      assert @hook.generate_rdoc
    end
    assert @hook.generate_ri

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

    @hook.delete_legacy_args args

    assert_empty args
  end

  def test_document
    skip 'RDoc 3 required' unless rdoc_3?

    options = RDoc::Options.new
    options.files = []

    rdoc = @hook.new_rdoc
    @hook.instance_variable_set :@rdoc, rdoc
    @hook.instance_variable_set :@file_info, []

    @hook.document 'darkfish', options, @a.doc_dir('rdoc')

    assert @hook.rdoc_installed?
  end unless rdoc_4

  def test_generate
    skip 'RDoc 3 required' unless rdoc_3?

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate

    assert @hook.rdoc_installed?
    assert @hook.ri_installed?

    rdoc = @hook.instance_variable_get :@rdoc

    refute rdoc.options.hyperlink_all
  end unless rdoc_4

  def test_generate_configuration_rdoc_array
    skip 'RDoc 3 required' unless rdoc_3?

    Gem.configuration[:rdoc] = %w[-A]

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate

    rdoc = @hook.instance_variable_get :@rdoc

    assert rdoc.options.hyperlink_all
  end unless rdoc_4

  def test_generate_configuration_rdoc_string
    skip 'RDoc 3 required' unless rdoc_3?

    Gem.configuration[:rdoc] = '-A'

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate

    rdoc = @hook.instance_variable_get :@rdoc

    assert rdoc.options.hyperlink_all
  end unless rdoc_4

  def test_generate_disabled
    @hook.generate_rdoc = false
    @hook.generate_ri   = false

    @hook.generate

    refute @hook.rdoc_installed?
    refute @hook.ri_installed?
  end

  def test_generate_force
    skip 'RDoc 3 required' unless rdoc_3?

    FileUtils.mkdir_p @a.doc_dir 'ri'
    FileUtils.mkdir_p @a.doc_dir 'rdoc'
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.force = true

    @hook.generate

    assert_path_exists File.join(@a.doc_dir('rdoc'), 'index.html')
    assert_path_exists File.join(@a.doc_dir('ri'),   'cache.ri')
  end unless rdoc_4

  def test_generate_no_overwrite
    skip 'RDoc 3 required' unless rdoc_3?

    FileUtils.mkdir_p @a.doc_dir 'ri'
    FileUtils.mkdir_p @a.doc_dir 'rdoc'
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate

    refute_path_exists File.join(@a.doc_dir('rdoc'), 'index.html')
    refute_path_exists File.join(@a.doc_dir('ri'),   'cache.ri')
  end unless rdoc_4

  def test_generate_legacy
    skip 'RDoc < 3.8 required' if rdoc_3_8_or_better?

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate_legacy

    assert @hook.rdoc_installed?
    assert @hook.ri_installed?
  end unless rdoc_4

  def test_legacy_rdoc
    skip 'RDoc < 3.8 required' if rdoc_3_8_or_better?

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.legacy_rdoc '--op', @a.doc_dir('rdoc')

    assert @hook.rdoc_installed?
  end unless rdoc_4

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
    skip 'skipped in root privilege' if Process.uid.zero?
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
    skip 'skipped in root privilege' if Process.uid.zero?
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
