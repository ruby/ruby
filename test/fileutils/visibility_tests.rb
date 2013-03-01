require 'test/unit'
require 'fileutils'

class TestFileUtils < Test::Unit::TestCase
end

##
# These tests are reused in the FileUtils::Verbose, FileUtils::NoWrite and
# FileUtils::DryRun tests

module TestFileUtils::Visibility

  FileUtils::METHODS.each do |m|
    define_method "test_singleton_visibility_#{m}" do
      assert @fu_module.respond_to?(m, true),
             "FileUtils::Verbose.#{m} is not defined"
      assert @fu_module.respond_to?(m, false),
             "FileUtils::Verbose.#{m} is not public"
    end

    define_method "test_visibility_#{m}" do
      assert respond_to?(m, true),
             "FileUtils::Verbose\##{m} is not defined"
      assert @fu_module.private_method_defined?(m),
             "FileUtils::Verbose\##{m} is not private"
    end
  end

  FileUtils::StreamUtils_.private_instance_methods.each do |m|
    define_method "test_singleton_visibility_#{m}" do
      assert @fu_module.respond_to?(m, true),
             "FileUtils::Verbose\##{m} is not defined"
    end

    define_method "test_visibility_#{m}" do
      assert respond_to?(m, true),
             "FileUtils::Verbose\##{m} is not defined"
    end
  end

end
