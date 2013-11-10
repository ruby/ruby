require "rubygems/test_case"
require "rubygems/stub_specification"

class TestStubSpecification < Gem::TestCase
  SPECIFICATIONS = File.expand_path(File.join("..", "specifications"), __FILE__)
  FOO = File.join SPECIFICATIONS, "foo-0.0.1.gemspec"
  BAR = File.join SPECIFICATIONS, "bar-0.0.2.gemspec"

  def setup
    super

    @foo = Gem::StubSpecification.new FOO
  end

  def test_initialize
    assert_equal "foo", @foo.name
    assert_equal Gem::Version.new("0.0.1"), @foo.version
    assert_equal Gem::Platform.new("mswin32"), @foo.platform
    assert_equal ["lib", "lib/f oo/ext"], @foo.require_paths
    assert @foo.stubbed?
  end

  def test_initialize_extension
    stub = stub_with_extension

    ext_install_dir = Pathname(stub.extension_install_dir)
    full_gem_path = Pathname(stub.full_gem_path)
    relative_install_dir = ext_install_dir.relative_path_from full_gem_path
    relative_install_dir = relative_install_dir.to_s

    assert_equal 'stub_e',                      stub.name
    assert_equal v(2),                          stub.version
    assert_equal Gem::Platform::RUBY,           stub.platform
    assert_equal ['lib', relative_install_dir], stub.require_paths
    assert_equal %w[ext/stub_e/extconf.rb],     stub.extensions
  end

  def test_initialize_missing_stubline
    stub = Gem::StubSpecification.new(BAR)
    assert_equal "bar", stub.name
    assert_equal Gem::Version.new("0.0.2"), stub.version
    assert_equal Gem::Platform.new("ruby"), stub.platform
    assert_equal ["lib"], stub.require_paths
    assert !stub.stubbed?
  end

  def test_contains_requirable_file_eh
    stub = stub_without_extension
    code_rb = File.join stub.gem_dir, 'lib', 'code.rb'
    FileUtils.mkdir_p File.dirname code_rb
    FileUtils.touch code_rb

    assert stub.contains_requirable_file? 'code'
  end

  def test_contains_requirable_file_eh_extension
    stub_with_extension do |stub|
      extconf_rb = File.join stub.gem_dir, stub.extensions.first
      FileUtils.mkdir_p File.dirname extconf_rb

      open extconf_rb, 'w' do |f|
        f.write <<-'RUBY'
          open 'Makefile', 'w' do |f|
            f.puts "clean:\n\techo cleaned"
            f.puts "default:\n\techo built"
            f.puts "install:\n\techo installed"
          end
        RUBY
      end

      refute stub.contains_requirable_file? 'nonexistent'

      assert_path_exists stub.extension_install_dir
    end
  end

  def test_full_require_paths
    stub = stub_with_extension

    expected = [
      File.join(stub.full_gem_path, 'lib'),
      stub.extension_install_dir,
    ]

    assert_equal expected, stub.full_require_paths
  end

  def test_to_spec
    assert @foo.to_spec.is_a?(Gem::Specification)
    assert_equal "foo", @foo.to_spec.name
  end

  def stub_with_extension
    spec = File.join @gemhome, 'specifications', 'stub_e-2.gemspec'
    open spec, 'w' do |io|
      io.write <<-STUB
# -*- encoding: utf-8 -*-
# stub: stub_e 2 ruby lib
# stub: ext/stub_e/extconf.rb

Gem::Specification.new do |s|
  s.name = 'stub_e'
  s.version = Gem::Version.new '2'
  s.extensions = ['ext/stub_e/extconf.rb']
  s.installed_by_version = '2.2'
end
      STUB

      io.flush

      stub = Gem::StubSpecification.new io.path

      yield stub if block_given?

      return stub
    end
  end

  def stub_without_extension
    spec = File.join @gemhome, 'specifications', 'stub-2.gemspec'
    open spec, 'w' do |io|
      io.write <<-STUB
# -*- encoding: utf-8 -*-
# stub: stub 2 ruby lib

Gem::Specification.new do |s|
  s.name = 'stub'
  s.version = Gem::Version.new '2'
end
      STUB

      io.flush

      stub = Gem::StubSpecification.new io.path

      yield stub if block_given?

      return stub
    end
  end

end

