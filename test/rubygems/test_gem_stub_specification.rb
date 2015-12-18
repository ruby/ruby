# frozen_string_literal: false
require "rubygems/test_case"
require "rubygems/stub_specification"

class TestStubSpecification < Gem::TestCase
  SPECIFICATIONS = File.expand_path(File.join("..", "specifications"), __FILE__)
  FOO = File.join SPECIFICATIONS, "foo-0.0.1-x86-mswin32.gemspec"
  BAR = File.join SPECIFICATIONS, "bar-0.0.2.gemspec"

  def setup
    super

    @base_dir = File.dirname(SPECIFICATIONS)
    @gems_dir = File.join File.dirname(SPECIFICATIONS), 'gem'
    @foo = Gem::StubSpecification.gemspec_stub FOO, @base_dir, @gems_dir
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

    assert_equal 'stub_e',                    stub.name
    assert_equal v(2),                        stub.version
    assert_equal Gem::Platform::RUBY,         stub.platform
    assert_equal [stub.extension_dir, 'lib'], stub.require_paths
    assert_equal %w[ext/stub_e/extconf.rb],   stub.extensions
  end

  def test_initialize_missing_stubline
    stub = Gem::StubSpecification.gemspec_stub(BAR, @base_dir, @gems_dir)
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
      _, err = capture_io do
        refute stub.contains_requirable_file? 'nonexistent'
      end

      expected = "Ignoring stub_e-2 because its extensions are not built.  " +
                 "Try: gem pristine stub_e --version 2\n"

      assert_equal expected, err
    end
  end

  def test_full_require_paths
    stub = stub_with_extension

    expected = [
      File.join(stub.full_gem_path, 'lib'),
      stub.extension_dir,
    ]

    assert_equal expected, stub.full_require_paths
  end

  def test_lib_dirs_glob
    stub = stub_without_extension

    assert_equal File.join(stub.full_gem_path, 'lib'), stub.lib_dirs_glob
  end

  def test_matches_for_glob
    stub = stub_without_extension
    code_rb = File.join stub.gem_dir, 'lib', 'code.rb'
    FileUtils.mkdir_p File.dirname code_rb
    FileUtils.touch code_rb

    assert_equal code_rb, stub.matches_for_glob('code*').first
  end

  def test_missing_extensions_eh
    stub = stub_with_extension do |s|
      extconf_rb = File.join s.gem_dir, s.extensions.first
      FileUtils.mkdir_p File.dirname extconf_rb

      open extconf_rb, 'w' do |f|
        f.write <<-'RUBY'
        open 'Makefile', 'w' do |f|
          f.puts "clean:\n\techo clean"
          f.puts "default:\n\techo built"
          f.puts "install:\n\techo installed"
        end
        RUBY
      end
    end

    assert stub.missing_extensions?

    stub.build_extensions

    refute stub.missing_extensions?
  end

  def test_missing_extensions_eh_default_gem
    spec = new_default_spec 'default', 1
    spec.extensions << 'extconf.rb'

    open spec.loaded_from, 'w' do |io|
      io.write spec.to_ruby_for_cache
    end

    default_spec = Gem::StubSpecification.gemspec_stub spec.loaded_from, spec.base_dir, spec.gems_dir

    refute default_spec.missing_extensions?
  end

  def test_missing_extensions_eh_none
    refute @foo.missing_extensions?
  end

  def test_to_spec
    real_foo = util_spec @foo.name, @foo.version
    real_foo.activate

    assert_equal @foo.version, Gem.loaded_specs[@foo.name].version,
                 'sanity check'

    assert_same real_foo, @foo.to_spec
  end

  def test_to_spec_with_other_specs_loaded_does_not_warn
    real_foo = util_spec @foo.name, @foo.version
    real_foo.activate
    bar = Gem::StubSpecification.gemspec_stub BAR, real_foo.base_dir, real_foo.gems_dir
    refute_predicate Gem.loaded_specs, :empty?
    assert bar.to_spec
  end

  def test_to_spec_activated
    assert @foo.to_spec.is_a?(Gem::Specification)
    assert_equal "foo", @foo.to_spec.name
    refute @foo.to_spec.instance_variable_get :@ignored
  end

  def test_to_spec_missing_extensions
    stub = stub_with_extension

    capture_io do
      stub.contains_requirable_file? 'nonexistent'
    end

    assert stub.to_spec.instance_variable_get :@ignored
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

      stub = Gem::StubSpecification.gemspec_stub io.path, @gemhome, File.join(@gemhome, 'gems')

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

      stub = Gem::StubSpecification.gemspec_stub io.path, @gemhome, File.join(@gemhome, 'gems')

      yield stub if block_given?

      return stub
    end
  end

end

