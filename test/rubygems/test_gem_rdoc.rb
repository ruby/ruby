# frozen_string_literal: true
require 'rubygems'
require 'rubygems/test_case'
require 'rubygems/rdoc'

class TestGemRDoc < Gem::TestCase
  Gem::RDoc.load_rdoc

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
      pend e.message
    end

    Gem.configuration[:rdoc] = nil
  end

  def test_initialize
    refute @hook.generate_rdoc
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

  def test_generate_disabled
    @hook.generate_rdoc = false
    @hook.generate_ri   = false

    @hook.generate

    refute @hook.rdoc_installed?
    refute @hook.ri_installed?
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
    pend 'chmod not supported' if Gem.win_platform?
    pend 'skipped in root privilege' if Process.uid.zero?
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
    pend 'chmod not supported' if Gem.win_platform?
    pend 'skipped in root privilege' if Process.uid.zero?
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
