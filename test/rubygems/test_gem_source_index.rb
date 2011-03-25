######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/test_case'
require 'rubygems/source_index'
require 'rubygems/config_file'

class TestGemSourceIndex < Gem::TestCase

  def setup
    super

    util_setup_fake_fetcher
  end

  def test_self_from_gems_in
    spec_dir = File.join @gemhome, 'specifications'

    FileUtils.rm_r spec_dir

    FileUtils.mkdir_p spec_dir

    a1 = quick_spec 'a', '1' do |spec| spec.author = 'author 1' end

    spec_file = File.join spec_dir, a1.spec_name

    File.open spec_file, 'w' do |fp|
      fp.write a1.to_ruby
    end

    si = Gem::SourceIndex.from_gems_in spec_dir

    assert_equal [spec_dir], si.spec_dirs
    assert_equal [a1.full_name], si.gems.keys
  end

  def test_self_load_specification
    spec_dir = File.join @gemhome, 'specifications'

    FileUtils.rm_r spec_dir

    FileUtils.mkdir_p spec_dir

    a1 = quick_spec 'a', '1' do |spec| spec.author = 'author 1' end

    spec_file = File.join spec_dir, a1.spec_name

    File.open spec_file, 'w' do |fp|
      fp.write a1.to_ruby
    end

    spec = Gem::SourceIndex.load_specification spec_file

    assert_equal a1.author, spec.author
  end

  def test_self_load_specification_utf_8
    spec_dir = File.join @gemhome, 'specifications'

    FileUtils.rm_r spec_dir

    FileUtils.mkdir_p spec_dir

    spec_file = File.join spec_dir, "utf-8.gemspec"
    spec_data = <<-SPEC
Gem::Specification.new do |s|
  s.name = %q{utf}
  s.version = "8"

  s.required_rubygems_version = Gem::Requirement.new(">= 0")
  s.authors = ["\317\200"]
  s.date = %q{2008-09-10}
  s.description = %q{This is a test description}
  s.email = %q{example@example.com}
  s.has_rdoc = true
  s.homepage = %q{http://example.com}
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.2.0}
  s.summary = %q{this is a summary}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
    SPEC

    spec_data.force_encoding 'UTF-8'

    File.open spec_file, 'w' do |io| io.write spec_data end

    spec = Gem::SourceIndex.load_specification spec_file

    pi = "\317\200"
    pi.force_encoding 'UTF-8' if pi.respond_to? :force_encoding

    assert_equal pi, spec.author
  end if Gem.ruby_version > Gem::Version.new('1.9')

  def test_self_load_specification_exception
    spec_dir = File.join @gemhome, 'specifications'

    FileUtils.mkdir_p spec_dir

    spec_file = File.join spec_dir, 'a-1.gemspec'

    File.open spec_file, 'w' do |fp|
      fp.write 'raise Exception, "epic fail"'
    end

    out, err = capture_io do
      assert_equal nil, Gem::SourceIndex.load_specification(spec_file)
    end

    assert_equal '', out

    expected = "Invalid gemspec in [#{spec_file}]: epic fail\n"
    assert_equal expected, err
  end

  def test_self_load_specification_interrupt
    spec_dir = File.join @gemhome, 'specifications'

    FileUtils.mkdir_p spec_dir

    spec_file = File.join spec_dir, 'a-1.gemspec'

    File.open spec_file, 'w' do |fp|
      fp.write 'raise Interrupt, "^C"'
    end

    use_ui @ui do
      assert_raises Interrupt do
        Gem::SourceIndex.load_specification(spec_file)
      end
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error
  end

  def test_self_load_specification_syntax_error
    spec_dir = File.join @gemhome, 'specifications'

    FileUtils.mkdir_p spec_dir

    spec_file = File.join spec_dir, 'a-1.gemspec'

    File.open spec_file, 'w' do |fp|
      fp.write '1 +'
    end

    out, err = capture_io do
      assert_equal nil, Gem::SourceIndex.load_specification(spec_file)
    end

    assert_equal '', out

    assert_match(/syntax error/, err)
  end

  def test_self_load_specification_system_exit
    spec_dir = File.join @gemhome, 'specifications'

    FileUtils.mkdir_p spec_dir

    spec_file = File.join spec_dir, 'a-1.gemspec'

    File.open spec_file, 'w' do |fp|
      fp.write 'raise SystemExit, "bye-bye"'
    end

    use_ui @ui do
      assert_raises SystemExit do
        Gem::SourceIndex.load_specification(spec_file)
      end
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error
  end

  def test_create_from_directory
    # TODO
  end

  def test_find_name
    assert_equal [@a1, @a2, @a3a], @source_index.find_name('a')
    assert_equal [@a2], @source_index.find_name('a', '= 2')
    assert_equal [], @source_index.find_name('bogusstring')
    assert_equal [], @source_index.find_name('a', '= 3')

    source_index = Gem::SourceIndex.new
    source_index.add_spec @a1
    source_index.add_spec @a2

    assert_equal [@a1], source_index.find_name(@a1.name, '= 1')

    r1 = Gem::Requirement.create '= 1'
    assert_equal [@a1], source_index.find_name(@a1.name, r1)
  end

  def test_find_name_empty_cache
    empty_source_index = Gem::SourceIndex.new({})
    assert_equal [], empty_source_index.find_name("foo")
  end

  def test_latest_specs
    p1_ruby = quick_spec 'p', '1'
    p1_platform = quick_spec 'p', '1' do |spec|
      spec.platform = Gem::Platform::CURRENT
    end

    a1_platform = quick_spec @a1.name, (@a1.version) do |s|
      s.platform = Gem::Platform.new 'x86-my_platform1'
    end

    a2_platform = quick_spec @a2.name, (@a2.version) do |s|
      s.platform = Gem::Platform.new 'x86-my_platform1'
    end

    a2_platform_other = quick_spec @a2.name, (@a2.version) do |s|
      s.platform = Gem::Platform.new 'x86-other_platform1'
    end

    a3_platform_other = quick_spec @a2.name, (@a2.version.bump) do |s|
      s.platform = Gem::Platform.new 'x86-other_platform1'
    end

    @source_index.add_spec p1_ruby
    @source_index.add_spec p1_platform
    @source_index.add_spec a1_platform
    @source_index.add_spec a2_platform
    @source_index.add_spec a2_platform_other
    @source_index.add_spec a3_platform_other

    expected = [
      @a2.full_name,
      a2_platform.full_name,
      a3_platform_other.full_name,
      @c1_2.full_name,
      @a_evil9.full_name,
      p1_ruby.full_name,
      p1_platform.full_name,
    ].sort

    latest_specs = @source_index.latest_specs.map { |s| s.full_name }.sort

    assert_equal expected, latest_specs
  end

  def test_load_gems_in
    spec_dir1 = File.join @gemhome, 'specifications'
    spec_dir2 = File.join @tempdir, 'gemhome2', 'specifications'

    FileUtils.rm_r spec_dir1

    FileUtils.mkdir_p spec_dir1
    FileUtils.mkdir_p spec_dir2

    a1 = quick_spec 'a', '1' do |spec| spec.author = 'author 1' end
    a2 = quick_spec 'a', '1' do |spec| spec.author = 'author 2' end

    File.open File.join(spec_dir1, a1.spec_name), 'w' do |fp|
      fp.write a1.to_ruby
    end

    File.open File.join(spec_dir2, a2.spec_name), 'w' do |fp|
      fp.write a2.to_ruby
    end

    @source_index.load_gems_in spec_dir1, spec_dir2

    assert_equal a1.author, @source_index.specification(a1.full_name).author
  end

  def test_outdated
    util_setup_spec_fetcher

    assert_equal [], @source_index.outdated

    updated = quick_spec @a2.name, (@a2.version.bump)
    util_setup_spec_fetcher updated

    assert_equal [updated.name], @source_index.outdated

    updated_platform = quick_spec @a2.name, (updated.version.bump) do |s|
      s.platform = Gem::Platform.new 'x86-other_platform1'
    end

    util_setup_spec_fetcher updated, updated_platform

    assert_equal [updated_platform.name], @source_index.outdated
  end

  def test_prerelease_specs_kept_in_right_place
    gem_a1_alpha = quick_spec 'abba', '1.a'
    @source_index.add_spec gem_a1_alpha

    refute @source_index.latest_specs.include?(gem_a1_alpha)
    assert @source_index.latest_specs(true).include?(gem_a1_alpha)
    assert @source_index.find_name(gem_a1_alpha.full_name).empty?
    assert @source_index.prerelease_specs.include?(gem_a1_alpha)
  end

  def test_refresh_bang
    a1_spec = File.join @gemhome, "specifications", @a1.spec_name

    FileUtils.mv a1_spec, @tempdir

    source_index = Gem::SourceIndex.from_installed_gems

    refute source_index.gems.include?(@a1.full_name)

    FileUtils.mv File.join(@tempdir, @a1.spec_name), a1_spec

    source_index.refresh!

    assert source_index.gems.include?(@a1.full_name)
  end

  def test_refresh_bang_not_from_dir
    source_index = Gem::SourceIndex.new

    e = assert_raises RuntimeError do
      source_index.refresh!
    end

    assert_equal 'source index not created from disk', e.message
  end

  def test_remove_spec
    deleted = @source_index.remove_spec 'a-1'

    assert_equal %w[a-2 a-3.a a_evil-9 c-1.2],
                 @source_index.all_gems.values.map { |s| s.full_name }.sort

    deleted = @source_index.remove_spec 'a-3.a'

    assert_equal %w[a-2 a_evil-9 c-1.2],
                 @source_index.all_gems.values.map { |s| s.full_name }.sort
  end

  def test_search
    requirement = Gem::Requirement.create '= 9'
    with_version = Gem::Dependency.new(/^a/, requirement)
    assert_equal [@a_evil9], @source_index.search(with_version)

    with_default = Gem::Dependency.new(/^a/, Gem::Requirement.default)
    assert_equal [@a1, @a2, @a3a, @a_evil9], @source_index.search(with_default)

    c1_1_dep = Gem::Dependency.new 'c', '~> 1.1'
    assert_equal [@c1_2], @source_index.search(c1_1_dep)
  end

  def test_search_platform
    util_set_arch 'x86-my_platform1'

    a1 = quick_spec 'a', '1'
    a1_mine = quick_spec 'a', '1' do |s|
      s.platform = Gem::Platform.new 'x86-my_platform1'
    end
    a1_other = quick_spec 'a', '1' do |s|
      s.platform = Gem::Platform.new 'x86-other_platform1'
    end

    si = Gem::SourceIndex.new(a1.full_name => a1, a1_mine.full_name => a1_mine,
                              a1_other.full_name => a1_other)

    dep = Gem::Dependency.new 'a', Gem::Requirement.new('1')

    gems = si.search dep, true

    assert_equal [a1, a1_mine], gems.sort
  end

  def test_signature
    sig = @source_index.gem_signature('foo-1.2.3')
    assert_equal 64, sig.length
    assert_match(/^[a-f0-9]{64}$/, sig)
  end

  def test_specification
    assert_equal @a1, @source_index.specification(@a1.full_name)

    assert_nil @source_index.specification("foo-1.2.4")
  end

  def test_index_signature
    sig = @source_index.index_signature
    assert_match(/^[a-f0-9]{64}$/, sig)
  end

end

