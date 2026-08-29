# frozen_string_literal: false
require 'test/unit'
require 'resolv'

class TestResolvDomainName < Test::Unit::TestCase
  def test_valid_names
    longest_valid_name = ('a' * 63 + '.') * 3 + 'b' * 61
    valid_names = [
      'com',
      'com.',
      'example.com',
      'example.com.',
      longest_valid_name,
      longest_valid_name + '.']
    
    valid_names.each do |domain_name|
      assert_nothing_raised(ArgumentError) do
        Resolv::DNS::Name.create(domain_name)
      end
    end
  end

  def test_invalid_names
    invalid_names = [
      '',
      '.example.com',
      'example..com',
      'a' * 64 + '.com',
      ('a' * 63 + '.') * 3 + 'b' * 62]
    
    invalid_names.each do |domain_name|
      assert_raise(ArgumentError) do
        Resolv::DNS::Name.create(domain_name)
      end
    end
  end
end
