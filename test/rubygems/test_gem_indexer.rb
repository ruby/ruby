#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')

require 'rubygems/indexer'

unless ''.respond_to? :to_xs then
  warn "Gem::Indexer tests are being skipped.  Install builder gem."
end

class TestGemIndexer < RubyGemTestCase

  def setup
    super

    util_make_gems

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

  def test_generate_index
    use_ui @ui do
      @indexer.generate_index
    end

    assert File.exist?(File.join(@tempdir, 'yaml'))
    assert File.exist?(File.join(@tempdir, 'yaml.Z'))
    assert File.exist?(File.join(@tempdir, "Marshal.#{@marshal_version}"))
    assert File.exist?(File.join(@tempdir, "Marshal.#{@marshal_version}.Z"))

    quickdir = File.join @tempdir, 'quick'
    marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

    assert File.directory?(quickdir)
    assert File.directory?(marshal_quickdir)

    assert_indexed quickdir, "index"
    assert_indexed quickdir, "index.rz"

    assert_indexed quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@a2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@b2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@c1_2.full_name}.gemspec.rz"

    assert_indexed quickdir, "#{@pl1.original_name}.gemspec.rz"
    deny_indexed quickdir, "#{@pl1.full_name}.gemspec.rz"

    assert_indexed marshal_quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed marshal_quickdir, "#{@a2.full_name}.gemspec.rz"

    deny_indexed quickdir, "#{@c1_2.full_name}.gemspec"
    deny_indexed marshal_quickdir, "#{@c1_2.full_name}.gemspec"
  end

  def test_generate_index_ui
    use_ui @ui do
      @indexer.generate_index
    end

    expected = <<-EOF
Generating index for 5 gems in #{@tempdir}
.....
Loaded all gems
Generating master indexes (this may take a while)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_generate_index_contents
    use_ui @ui do
      @indexer.generate_index
    end

    yaml_path = File.join(@tempdir, 'yaml')
    dump_path = File.join(@tempdir, "Marshal.#{@marshal_version}")

    yaml_index = YAML.load_file(yaml_path)
    dump_str = nil
    File.open dump_path, 'rb' do |fp| dump_str = fp.read end
    dump_index = Marshal.load dump_str

    dump_index.each do |_,gem|
      gem.send :remove_instance_variable, :@loaded
    end

    assert_equal yaml_index, dump_index,
                 "expected YAML and Marshal to produce identical results"
  end

  def assert_indexed(dir, name)
    file = File.join dir, name
    assert File.exist?(file), "#{file} does not exist"
  end

  def deny_indexed(dir, name)
    file = File.join dir, name
    assert !File.exist?(file), "#{file} exists"
  end

end if ''.respond_to? :to_xs

