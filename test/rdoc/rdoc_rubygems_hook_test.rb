# frozen_string_literal: true
require 'rubygems'
require 'fileutils'
require 'tmpdir'
require_relative '../../lib/rdoc/rubygems_hook'
require 'test/unit'

class RDocRubyGemsHookTest < Test::Unit::TestCase
  def setup
    @a = Gem::Specification.new do |s|
      s.platform    = Gem::Platform::RUBY
      s.name        = "a"
      s.version     = 2
      s.rdoc_options = %w[--main MyTitle]
      s.extra_rdoc_files = %w[README]
    end
    @tempdir = File.realpath(Dir.mktmpdir("test_rubygems_hook_"))

    @orig_envs = %w[
      GEM_VENDOR
      GEMRC
      XDG_CACHE_HOME
      XDG_CONFIG_HOME
      XDG_DATA_HOME
      SOURCE_DATE_EPOCH
      BUNDLER_VERSION
      HOME
      RDOCOPT
    ].map {|e| [e, ENV.delete(e)]}.to_h
    ENV["HOME"] = @tempdir

    Gem.configuration = nil

    @a.instance_variable_set(:@doc_dir, File.join(@tempdir, "doc"))
    @a.instance_variable_set(:@gem_dir, File.join(@tempdir, "a-2"))
    @a.instance_variable_set(:@full_gem_path, File.join(@tempdir, "a-2"))
    @a.loaded_from = File.join(@tempdir, 'a-2', 'a-2.gemspec')

    FileUtils.mkdir_p File.join(@tempdir, 'a-2', 'lib')
    FileUtils.touch   File.join(@tempdir, 'a-2', 'README')
    File.open(File.join(@tempdir, 'a-2', 'lib', 'a.rb'), 'w') do |f|
      f.puts '# comment'
      f.puts '# :include: include.txt'
      f.puts 'class A; end'
    end
    File.open(File.join(@tempdir, 'a-2', 'include.txt'), 'w') do |f|
      f.puts 'included content'
    end

    @hook = RDoc::RubyGemsHook.new @a

    begin
      RDoc::RubyGemsHook.load_rdoc
    rescue Gem::DocumentError => e
      omit e.message
    end
    @old_ui = Gem::DefaultUserInteraction.ui
    Gem::DefaultUserInteraction.ui = Gem::SilentUI.new
  end

  def teardown
    ui = Gem::DefaultUserInteraction.ui
    Gem::DefaultUserInteraction.ui = @old_ui
    FileUtils.rm_rf @tempdir
    ui.close
    ENV.update(@orig_envs)
  end

  def test_initialize
    refute @hook.generate_rdoc
    assert @hook.generate_ri

    rdoc = RDoc::RubyGemsHook.new @a, false, false

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
    rdoc.store = RDoc::Store.new(options)
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

    klass = rdoc.store.find_class_named('A')
    refute_nil klass
    assert_includes klass.comment.text, 'included content'
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
    Gem::Deprecate.skip_during do
      if Gem.respond_to?(:default_specifications_dir)
        klass = Gem
      else
        klass = Gem::Specification
      end
      @a.loaded_from = File.join klass.default_specifications_dir, 'a.gemspec'
    end

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

    assert_path_not_exist File.join(@a.doc_dir('rdoc'), 'index.html')
    assert_path_exist File.join(@a.doc_dir('ri'),   'cache.ri')
  end

  def test_generate_rubygems_compatible
    original_default_gem_method = RDoc::RubygemsHook.method(:default_gem?)
    RDoc::RubygemsHook.singleton_class.remove_method(:default_gem?)
    RDoc::RubygemsHook.define_singleton_method(:default_gem?) { true }
    FileUtils.mkdir_p @a.doc_dir 'ri'
    FileUtils.mkdir_p @a.doc_dir 'rdoc'
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    # rubygems/lib/rubygems/commands/rdoc_command.rb calls this
    hook = RDoc::RubygemsHook.new @a, true, true
    hook.force = true
    hook.generate

    assert_path_exist File.join(@a.doc_dir('rdoc'), 'index.html')
  ensure
    RDoc::RubygemsHook.singleton_class.remove_method(:default_gem?)
    RDoc::RubygemsHook.define_singleton_method(:default_gem?, &original_default_gem_method)
  end

  def test_generate_no_overwrite
    FileUtils.mkdir_p @a.doc_dir 'ri'
    FileUtils.mkdir_p @a.doc_dir 'rdoc'
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')

    @hook.generate

    assert_path_not_exist File.join(@a.doc_dir('rdoc'), 'index.html')
    assert_path_not_exist File.join(@a.doc_dir('ri'),   'cache.ri')
  end

  def test_generate_with_ri_opt
    @a.rdoc_options << '--ri'
    FileUtils.mkdir_p @a.doc_dir
    FileUtils.mkdir_p File.join(@a.gem_dir, 'lib')
    @hook.generate_rdoc = true
    @hook.generate_ri   = true
    @hook.generate

    assert_path_exist File.join(@a.doc_dir('rdoc'), 'index.html')
    assert_path_exist File.join(@a.doc_dir('ri'),   'cache.ri')
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

    assert_path_exist @a.doc_dir
  end

  def test_remove_unwritable
    omit 'chmod not supported' if Gem.win_platform?
    omit "assumes that euid is not root" if Process.euid == 0

    FileUtils.mkdir_p @a.base_dir
    FileUtils.chmod 0, @a.base_dir

    e = assert_raise Gem::FilePermissionError do
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

    assert_path_exist @a.doc_dir
  end

  def test_setup_unwritable
    omit 'chmod not supported' if Gem.win_platform?
    omit "assumes that euid is not root" if Process.euid == 0

    FileUtils.mkdir_p @a.doc_dir
    FileUtils.chmod 0, @a.doc_dir

    e = assert_raise Gem::FilePermissionError do
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
