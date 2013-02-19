require 'test/unit'
require 'rbconfig'

class TestRbConfig < Test::Unit::TestCase
  def test_sitedirs
    RbConfig::MAKEFILE_CONFIG.each do |key, val|
      next unless /\Asite(?!arch)/ =~ key
      assert_match(/(?:\$\(|\/)site/, val, key)
    end
  end

  def test_vendordirs
    RbConfig::MAKEFILE_CONFIG.each do |key, val|
      next unless /\Avendor(?!arch)/ =~ key
      assert_match(/(?:\$\(|\/)vendor/, val, key)
    end
  end

  def test_archdirs
    RbConfig::MAKEFILE_CONFIG.each do |key, val|
      next unless /\A(?!site|vendor|archdir\z).*arch.*dir\z/ =~ key
      assert_match(/\$\(arch|\$\(rubyarchprefix\)/, val, key)
    end
  end

  def test_sitearchdirs
    bug7823 = '[ruby-dev:46964] [Bug #7823]'
    RbConfig::MAKEFILE_CONFIG.each do |key, val|
      next unless /\Asite.*arch.*dir\z/ =~ key
      assert_match(/\$\(sitearch|\$\(rubysitearchprefix\)/, val, "#{key} #{bug7823}")
    end
  end

  def test_vendorarchdirs
    bug7823 = '[ruby-dev:46964] [Bug #7823]'
    RbConfig::MAKEFILE_CONFIG.each do |key, val|
      next unless /\Avendor.*arch.*dir\z/ =~ key
      assert_match(/\$\(sitearch|\$\(rubysitearchprefix\)/, val, "#{key} #{bug7823}")
    end
  end
end
