require "irb"
require "stringio"

require_relative "helper"

module TestIRB
  class LocaleTestCase < TestCase
    def test_initialize_with_en
      locale = IRB::Locale.new("en_US.UTF-8")

      assert_equal("en", locale.lang)
      assert_equal("US", locale.territory)
      assert_equal("UTF-8", locale.encoding.name)
      assert_equal(nil, locale.modifier)
    end

    def test_initialize_with_ja
      locale = IRB::Locale.new("ja_JP.UTF-8")

      assert_equal("ja", locale.lang)
      assert_equal("JP", locale.territory)
      assert_equal("UTF-8", locale.encoding.name)
      assert_equal(nil, locale.modifier)
    end

    def test_initialize_with_legacy_ja_encoding_ujis
      original_stderr = $stderr
      $stderr = StringIO.new

      locale = IRB::Locale.new("ja_JP.ujis")

      assert_equal("ja", locale.lang)
      assert_equal("JP", locale.territory)
      assert_equal(Encoding::EUC_JP, locale.encoding)
      assert_equal(nil, locale.modifier)

      assert_include $stderr.string, "ja_JP.ujis is obsolete. use ja_JP.EUC-JP"
    ensure
      $stderr = original_stderr
    end

    def test_initialize_with_legacy_ja_encoding_euc
      original_stderr = $stderr
      $stderr = StringIO.new

      locale = IRB::Locale.new("ja_JP.euc")

      assert_equal("ja", locale.lang)
      assert_equal("JP", locale.territory)
      assert_equal(Encoding::EUC_JP, locale.encoding)
      assert_equal(nil, locale.modifier)

      assert_include $stderr.string, "ja_JP.euc is obsolete. use ja_JP.EUC-JP"
    ensure
      $stderr = original_stderr
    end

    %w(IRB_LANG LC_MESSAGES LC_ALL LANG).each do |env_var|
      define_method "test_initialize_with_#{env_var.downcase}" do
        original_values = {
          "IRB_LANG" => ENV["IRB_LANG"],
          "LC_MESSAGES" => ENV["LC_MESSAGES"],
          "LC_ALL" => ENV["LC_ALL"],
          "LANG" => ENV["LANG"],
        }

        ENV["IRB_LANG"] = ENV["LC_MESSAGES"] = ENV["LC_ALL"] = ENV["LANG"] = nil
        ENV[env_var] = "zh_TW.UTF-8"

        locale = IRB::Locale.new

        assert_equal("zh", locale.lang)
        assert_equal("TW", locale.territory)
        assert_equal("UTF-8", locale.encoding.name)
        assert_equal(nil, locale.modifier)
      ensure
        original_values.each do |key, value|
          ENV[key] = value
        end
      end
    end
  end
end
