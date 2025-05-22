# frozen_string_literal: true
require_relative 'helper'

class RDocI18nLocaleTest < RDoc::TestCase

  def setup
    super
    @locale = locale('fr')

    @tmpdir = File.join Dir.tmpdir, "test_rdoc_i18n_locale_#{$$}"
    FileUtils.mkdir_p @tmpdir

    @locale_dir = @tmpdir
  end

  def teardown
    FileUtils.rm_rf @tmpdir
    super
  end

  def test_name
    assert_equal 'fr', locale('fr').name
  end

  def test_load_nonexistent_po
    locale = File.join(@locale_dir, 'nonexsitent-locale')
    refute_file locale
    refute @locale.load(locale)
  end

  def test_load_existent_po
    begin
      require 'gettext/po_parser'
    rescue LoadError
      omit 'gettext gem is not found'
    end

    fr_locale_dir = File.join @locale_dir, 'fr'
    FileUtils.mkdir_p fr_locale_dir
    File.open File.join(fr_locale_dir, 'rdoc.po'), 'w' do |po|
      po.puts <<-PO
msgid ""
msgstr ""
"Language: fr\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"

msgid "Hello"
msgstr "Bonjour"
      PO
    end

    assert @locale.load(@locale_dir)
    assert_equal 'Bonjour', @locale.translate('Hello')
  end

  def test_translate_existent_message
    messages = @locale.instance_variable_get(:@messages)
    messages['Hello'] = 'Bonjour'
    assert_equal 'Bonjour', @locale.translate('Hello')
  end

  def test_translate_nonexistent_message
    assert_equal 'Hello', @locale.translate('Hello')
  end

  private

  def locale(name)
    RDoc::I18n::Locale.new(name)
  end

end
