#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')

require 'rubygems/indexer'

unless ''.respond_to? :to_xs then
  warn "Gem::Indexer tests are being skipped.  Install builder gem."
end

class TestGemIndexer < RubyGemTestCase

  def setup
    super

    util_make_gems

    @d2_0 = quick_gem 'd', '2.0'
    util_build_gem @d2_0

    gems = File.join(@tempdir, 'gems')
    FileUtils.mkdir_p gems
    cache_gems = File.join @gemhome, 'cache', '*.gem'
    FileUtils.mv Dir[cache_gems], gems

    @indexer = Gem::Indexer.new @tempdir
  end

  def test_initialize
    assert_equal @tempdir, @indexer.dest_directory
    assert_equal File.join(Dir.tmpdir, "gem_generate_index_#{$$}"),
                 @indexer.directory
  end

  def test_build_indicies
    spec = quick_gem 'd', '2.0'
    spec.instance_variable_set :@original_platform, ''

    @indexer.make_temp_directories

    index = Gem::SourceIndex.new
    index.add_spec spec

    use_ui @ui do
      @indexer.build_indicies index
    end

    specs_path = File.join @indexer.directory, "specs.#{@marshal_version}"
    specs_dump = Gem.read_binary specs_path
    specs = Marshal.load specs_dump

    expected = [
      ['d',      Gem::Version.new('2.0'), 'ruby'],
    ]

    assert_equal expected, specs, 'specs'

    latest_specs_path = File.join @indexer.directory,
                                  "latest_specs.#{@marshal_version}"
    latest_specs_dump = Gem.read_binary latest_specs_path
    latest_specs = Marshal.load latest_specs_dump

    expected = [
      ['d',      Gem::Version.new('2.0'), 'ruby'],
    ]

    assert_equal expected, latest_specs, 'latest_specs'
  end

  def test_generate_index
    use_ui @ui do
      @indexer.generate_index
    end

    assert_indexed @tempdir, 'yaml'
    assert_indexed @tempdir, 'yaml.Z'
    assert_indexed @tempdir, "Marshal.#{@marshal_version}"
    assert_indexed @tempdir, "Marshal.#{@marshal_version}.Z"

    quickdir = File.join @tempdir, 'quick'
    marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

    assert File.directory?(quickdir)
    assert File.directory?(marshal_quickdir)

    assert_indexed quickdir, "index"
    assert_indexed quickdir, "index.rz"

    quick_index = File.read File.join(quickdir, 'index')
    expected = <<-EOF
a-1
a-2
a_evil-9
b-2
c-1.2
d-2.0
pl-1-i386-linux
    EOF

    assert_equal expected, quick_index

    assert_indexed quickdir, "latest_index"
    assert_indexed quickdir, "latest_index.rz"

    latest_quick_index = File.read File.join(quickdir, 'latest_index')
    expected = <<-EOF
a-2
a_evil-9
b-2
c-1.2
d-2.0
pl-1-i386-linux
    EOF

    assert_equal expected, latest_quick_index

    assert_indexed quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@a2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@b2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@c1_2.full_name}.gemspec.rz"

    assert_indexed quickdir, "#{@pl1.original_name}.gemspec.rz"
    refute_indexed quickdir, "#{@pl1.full_name}.gemspec.rz"

    assert_indexed marshal_quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed marshal_quickdir, "#{@a2.full_name}.gemspec.rz"

    refute_indexed quickdir, "#{@c1_2.full_name}.gemspec"
    refute_indexed marshal_quickdir, "#{@c1_2.full_name}.gemspec"

    assert_indexed @tempdir, "specs.#{@marshal_version}"
    assert_indexed @tempdir, "specs.#{@marshal_version}.gz"

    assert_indexed @tempdir, "latest_specs.#{@marshal_version}"
    assert_indexed @tempdir, "latest_specs.#{@marshal_version}.gz"
  end

  def test_generate_index_ui
    use_ui @ui do
      @indexer.generate_index
    end

    expected = <<-EOF
Loading 7 gems from #{@tempdir}
.......
Loaded all gems
Generating quick index gemspecs for 7 gems
.......
Complete
Generating specs index
Generating latest specs index
Generating quick index
Generating latest index
Generating Marshal master index
Generating YAML master index for 7 gems (this may take a while)
.......
Complete
Compressing indicies
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_generate_index_master
    use_ui @ui do
      @indexer.generate_index
    end

    yaml_path = File.join @tempdir, 'yaml'
    dump_path = File.join @tempdir, "Marshal.#{@marshal_version}"

    yaml_index = YAML.load_file yaml_path
    dump_index = Marshal.load Gem.read_binary(dump_path)

    dump_index.each do |_,gem|
      gem.send :remove_instance_variable, :@loaded
    end

    assert_equal yaml_index, dump_index,
                 "expected YAML and Marshal to produce identical results"
  end

  def test_generate_index_specs
    use_ui @ui do
      @indexer.generate_index
    end

    specs_path = File.join @tempdir, "specs.#{@marshal_version}"

    specs_dump = Gem.read_binary specs_path
    specs = Marshal.load specs_dump

    expected = [
      ['a',      Gem::Version.new(1),     'ruby'],
      ['a',      Gem::Version.new(2),     'ruby'],
      ['a_evil', Gem::Version.new(9),     'ruby'],
      ['b',      Gem::Version.new(2),     'ruby'],
      ['c',      Gem::Version.new('1.2'), 'ruby'],
      ['d',      Gem::Version.new('2.0'), 'ruby'],
      ['pl',     Gem::Version.new(1),     'i386-linux'],
    ]

    assert_equal expected, specs

    assert_same specs[0].first, specs[1].first,
                'identical names not identical'

    assert_same specs[0][1],    specs[-1][1],
                'identical versions not identical'

    assert_same specs[0].last, specs[1].last,
                'identical platforms not identical'

    refute_same specs[1][1], specs[5][1],
                'different versions not different'
  end

  def test_generate_index_latest_specs
    use_ui @ui do
      @indexer.generate_index
    end

    latest_specs_path = File.join @tempdir, "latest_specs.#{@marshal_version}"

    latest_specs_dump = Gem.read_binary latest_specs_path
    latest_specs = Marshal.load latest_specs_dump

    expected = [
      ['a',      Gem::Version.new(2),     'ruby'],
      ['a_evil', Gem::Version.new(9),     'ruby'],
      ['b',      Gem::Version.new(2),     'ruby'],
      ['c',      Gem::Version.new('1.2'), 'ruby'],
      ['d',      Gem::Version.new('2.0'), 'ruby'],
      ['pl',     Gem::Version.new(1),     'i386-linux'],
    ]

    assert_equal expected, latest_specs

    assert_same latest_specs[0][1],   latest_specs[2][1],
                'identical versions not identical'

    assert_same latest_specs[0].last, latest_specs[1].last,
                'identical platforms not identical'
  end

  def assert_indexed(dir, name)
    file = File.join dir, name
    assert File.exist?(file), "#{file} does not exist"
  end

  def refute_indexed(dir, name)
    file = File.join dir, name
    assert !File.exist?(file), "#{file} exists"
  end

end if ''.respond_to? :to_xs

