# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/request_set'
require 'rubygems/request_set/lockfile'
require 'rubygems/request_set/lockfile/tokenizer'
require 'rubygems/request_set/lockfile/parser'

class TestGemRequestSetLockfileParser < Gem::TestCase

  def setup
    super
    @gem_deps_file = 'gem.deps.rb'
    @lock_file = File.expand_path "#{@gem_deps_file}.lock"
    @set = Gem::RequestSet.new
  end

  def test_get
    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.new "\n"
    parser = tokenizer.make_parser nil, nil

    assert_equal :newline, parser.get.first
  end

  def test_get_type_mismatch
    filename = File.expand_path("#{@gem_deps_file}.lock")
    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.new "foo", filename, 1, 0
    parser = tokenizer.make_parser nil, nil

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      parser.get :section
    end

    expected =
      'unexpected token [:text, "foo"], expected :section (at line 1 column 0)'

    assert_equal expected, e.message

    assert_equal 1, e.line
    assert_equal 0, e.column
    assert_equal filename, e.path
  end

  def test_get_type_multiple
    filename = File.expand_path("#{@gem_deps_file}.lock")
    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.new "x", filename, 1
    parser = tokenizer.make_parser nil, nil

    assert parser.get [:text, :section]
  end

  def test_get_type_value_mismatch
    filename = File.expand_path("#{@gem_deps_file}.lock")
    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.new "x", filename, 1
    parser = tokenizer.make_parser nil, nil

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      parser.get :text, 'y'
    end

    expected =
      'unexpected token [:text, "x"], expected [:text, "y"] (at line 1 column 0)'

    assert_equal expected, e.message

    assert_equal 1, e.line
    assert_equal 0, e.column
    assert_equal File.expand_path("#{@gem_deps_file}.lock"), e.path
  end

  def test_parse
    write_lockfile <<-LOCKFILE.strip
GEM
  remote: #{@gem_repo}
  specs:
    a (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    platforms = []
    parse_lockfile @set, platforms

    assert_equal [dep('a')], @set.dependencies

    assert_equal [Gem::Platform::RUBY], platforms

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    assert lockfile_set, 'could not find a LockSet'

    assert_equal %w[a-2], lockfile_set.specs.map { |tuple| tuple.full_name }
  end

  def test_parse_dependencies
    write_lockfile <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a (>= 1, <= 2)
    LOCKFILE

    platforms = []
    parse_lockfile @set, platforms

    assert_equal [dep('a', '>= 1', '<= 2')], @set.dependencies

    assert_equal [Gem::Platform::RUBY], platforms

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    assert lockfile_set, 'could not find a LockSet'

    assert_equal %w[a-2], lockfile_set.specs.map { |tuple| tuple.full_name }
  end

  def test_parse_DEPENDENCIES_git
    write_lockfile <<-LOCKFILE
GIT
  remote: git://git.example/josevalim/rails-footnotes.git
  revision: 3a6ac1971e91d822f057650cc5916ebfcbd6ee37
  specs:
    rails-footnotes (3.7.9)
      rails (>= 3.0.0)

GIT
  remote: git://git.example/svenfuchs/i18n-active_record.git
  revision: 55507cf59f8f2173d38e07e18df0e90d25b1f0f6
  specs:
    i18n-active_record (0.0.2)
      i18n (>= 0.5.0)

GEM
  remote: http://gems.example/
  specs:
    i18n (0.6.9)
    rails (4.0.0)

PLATFORMS
  ruby

DEPENDENCIES
  i18n-active_record!
  rails-footnotes!
    LOCKFILE

    parse_lockfile @set, []

    expected = [
      dep('i18n-active_record', '= 0.0.2'),
      dep('rails-footnotes',    '= 3.7.9'),
    ]

    assert_equal expected, @set.dependencies
  end

  def test_parse_DEPENDENCIES_git_version
    write_lockfile <<-LOCKFILE
GIT
  remote: git://github.com/progrium/ruby-jwt.git
  revision: 8d74770c6cd92ea234b428b5d0c1f18306a4f41c
  specs:
    jwt (1.1)

GEM
  remote: http://gems.example/
  specs:

PLATFORMS
  ruby

DEPENDENCIES
  jwt (= 1.1)!
    LOCKFILE

    parse_lockfile @set, []

    expected = [
      dep('jwt', '= 1.1'),
    ]

    assert_equal expected, @set.dependencies
  end

  def test_parse_GEM
    write_lockfile <<-LOCKFILE
GEM
  specs:
    a (2)

PLATFORMS
  ruby

DEPENDENCIES
  a
    LOCKFILE

    parse_lockfile @set, []

    assert_equal [dep('a', '>= 0')], @set.dependencies

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    assert lockfile_set, 'found a LockSet'

    assert_equal %w[a-2], lockfile_set.specs.map { |s| s.full_name }
  end

  def test_parse_GEM_remote_multiple
    write_lockfile <<-LOCKFILE
GEM
  remote: https://gems.example/
  remote: https://other.example/
  specs:
    a (2)

PLATFORMS
  ruby

DEPENDENCIES
  a
    LOCKFILE

    parse_lockfile @set, []

    assert_equal [dep('a', '>= 0')], @set.dependencies

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    assert lockfile_set, 'found a LockSet'

    assert_equal %w[a-2], lockfile_set.specs.map { |s| s.full_name }

    assert_equal %w[https://gems.example/ https://other.example/],
                 lockfile_set.specs.flat_map { |s| s.sources.map{ |src| src.uri.to_s } }
  end

  def test_parse_GIT
    @set.instance_variable_set :@install_dir, 'install_dir'

    write_lockfile <<-LOCKFILE
GIT
  remote: git://example/a.git
  revision: master
  specs:
    a (2)
      b (>= 3)
      c

DEPENDENCIES
  a!
    LOCKFILE

    parse_lockfile @set, []

    assert_equal [dep('a', '= 2')], @set.dependencies

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    refute lockfile_set, 'fount a LockSet'

    git_set = @set.sets.find do |set|
      Gem::Resolver::GitSet === set
    end

    assert git_set, 'could not find a GitSet'

    assert_equal %w[a-2], git_set.specs.values.map { |s| s.full_name }

    assert_equal [dep('b', '>= 3'), dep('c')],
                 git_set.specs.values.first.dependencies

    expected = {
      'a' => %w[git://example/a.git master],
    }

    assert_equal expected, git_set.repositories
    assert_equal 'install_dir', git_set.root_dir
  end

  def test_parse_GIT_branch
    write_lockfile <<-LOCKFILE
GIT
  remote: git://example/a.git
  revision: 1234abc
  branch: 0-9-12-stable
  specs:
    a (2)
      b (>= 3)

DEPENDENCIES
  a!
    LOCKFILE

    parse_lockfile @set, []

    assert_equal [dep('a', '= 2')], @set.dependencies

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    refute lockfile_set, 'fount a LockSet'

    git_set = @set.sets.find do |set|
      Gem::Resolver::GitSet === set
    end

    assert git_set, 'could not find a GitSet'

    expected = {
      'a' => %w[git://example/a.git 1234abc],
    }

    assert_equal expected, git_set.repositories
  end

  def test_parse_GIT_ref
    write_lockfile <<-LOCKFILE
GIT
  remote: git://example/a.git
  revision: 1234abc
  ref: 1234abc
  specs:
    a (2)
      b (>= 3)

DEPENDENCIES
  a!
    LOCKFILE

    parse_lockfile @set, []

    assert_equal [dep('a', '= 2')], @set.dependencies

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    refute lockfile_set, 'fount a LockSet'

    git_set = @set.sets.find do |set|
      Gem::Resolver::GitSet === set
    end

    assert git_set, 'could not find a GitSet'

    expected = {
      'a' => %w[git://example/a.git 1234abc],
    }

    assert_equal expected, git_set.repositories
  end

  def test_parse_GIT_tag
    write_lockfile <<-LOCKFILE
GIT
  remote: git://example/a.git
  revision: 1234abc
  tag: v0.9.12
  specs:
    a (2)
      b (>= 3)

DEPENDENCIES
  a!
    LOCKFILE

    parse_lockfile @set, []

    assert_equal [dep('a', '= 2')], @set.dependencies

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    refute lockfile_set, 'fount a LockSet'

    git_set = @set.sets.find do |set|
      Gem::Resolver::GitSet === set
    end

    assert git_set, 'could not find a GitSet'

    expected = {
      'a' => %w[git://example/a.git 1234abc],
    }

    assert_equal expected, git_set.repositories
  end

  def test_parse_PATH
    _, _, directory = vendor_gem

    write_lockfile <<-LOCKFILE
PATH
  remote: #{directory}
  specs:
    a (1)
      b (2)

DEPENDENCIES
  a!
    LOCKFILE

    parse_lockfile @set, []

    assert_equal [dep('a', '= 1')], @set.dependencies

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    refute lockfile_set, 'found a LockSet'

    vendor_set = @set.sets.find do |set|
      Gem::Resolver::VendorSet === set
    end

    assert vendor_set, 'could not find a VendorSet'

    assert_equal %w[a-1], vendor_set.specs.values.map { |s| s.full_name }

    spec = vendor_set.load_spec 'a', nil, nil, nil

    assert_equal [dep('b', '= 2')], spec.dependencies
  end

  def test_parse_dependency
    write_lockfile ' 1)'

    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.from_file @lock_file
    parser = tokenizer.make_parser nil, nil

    parsed = parser.parse_dependency 'a', '='

    assert_equal dep('a', '= 1'), parsed

    write_lockfile ')'

    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.from_file @lock_file
    parser = tokenizer.make_parser nil, nil

    parsed = parser.parse_dependency 'a', '2'

    assert_equal dep('a', '= 2'), parsed
  end

  def test_parse_gem_specs_dependency
    write_lockfile <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b (= 3)
      c (~> 4)
      d
      e (~> 5.0, >= 5.0.1)
    b (3-x86_64-linux)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    platforms = []
    parse_lockfile @set, platforms

    assert_equal [dep('a')], @set.dependencies

    assert_equal [Gem::Platform::RUBY], platforms

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    assert lockfile_set, 'could not find a LockSet'

    assert_equal %w[a-2 b-3], lockfile_set.specs.map { |tuple| tuple.full_name }

    expected = [
      Gem::Platform::RUBY,
      Gem::Platform.new('x86_64-linux'),
    ]

    assert_equal expected, lockfile_set.specs.map { |tuple| tuple.platform }

    spec = lockfile_set.specs.first

    expected = [
      dep('b', '= 3'),
      dep('c', '~> 4'),
      dep('d'),
      dep('e', '~> 5.0', '>= 5.0.1'),
    ]

    assert_equal expected, spec.dependencies
  end

  def test_parse_missing
    assert_raises(Errno::ENOENT) do
      parse_lockfile @set, []
    end

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    refute lockfile_set
  end

  def write_lockfile(lockfile)
    File.open @lock_file, 'w' do |io|
      io.write lockfile
    end
  end

  def parse_lockfile(set, platforms)
    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.from_file @lock_file
    parser = tokenizer.make_parser set, platforms
    parser.parse
  end

end
