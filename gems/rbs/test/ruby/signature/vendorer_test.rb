require "test_helper"
require "open3"

class Ruby::Signature::VendorerTest < Minitest::Test
  Environment = Ruby::Signature::Environment
  EnvironmentLoader = Ruby::Signature::EnvironmentLoader
  Declarations = Ruby::Signature::AST::Declarations
  TypeName = Ruby::Signature::TypeName
  Namespace = Ruby::Signature::Namespace
  Vendorer = Ruby::Signature::Vendorer

  def mktmpdir
    Dir.mktmpdir do |path|
      yield Pathname(path)
    end
  end

  def test_vendor_stdlib
    mktmpdir do |path|
      vendor_dir = path + "vendor"
      vendorer = Vendorer.new(vendor_dir: vendor_dir)

      vendorer.stdlib!

      assert_operator vendor_dir + "stdlib/builtin", :directory?
      assert_operator vendor_dir + "stdlib/builtin/basic_object.rbs", :file?
      assert_operator vendor_dir + "stdlib/set", :directory?
      assert_operator vendor_dir + "stdlib/set/set.rbs", :file?
    end
  end

  def test_vendor_clean
    mktmpdir do |path|
      vendor_dir = path + "vendor"
      vendorer = Vendorer.new(vendor_dir: vendor_dir)

      vendorer.stdlib!

      assert_operator vendor_dir, :directory?

      vendorer.clean!

      refute_operator vendor_dir, :directory?
    end
  end

  def test_vendor_gem
    mktmpdir do |path|
      vendor_dir = path + "vendor"
      vendorer = Vendorer.new(vendor_dir: vendor_dir)

      vendorer.stdlib!
      vendorer.gem! "ruby-signature-amber", nil

      assert_operator vendor_dir + "stdlib", :directory?
      assert_operator vendor_dir + "gems/ruby-signature-amber", :directory?
    end
  end
end
