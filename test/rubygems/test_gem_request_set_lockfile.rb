require 'rubygems/test_case'
require 'rubygems/request_set'
require 'rubygems/request_set/lockfile'

class TestGemRequestSetLockfile < Gem::TestCase

  def setup
    super

    Gem::RemoteFetcher.fetcher = @fetcher = Gem::FakeFetcher.new

    util_set_arch 'i686-darwin8.10.1'

    @set = Gem::RequestSet.new

    @vendor_set = Gem::DependencyResolver::VendorSet.new

    @set.instance_variable_set :@vendor_set, @vendor_set

    @gem_deps_file = 'gem.deps.rb'

    @lockfile = Gem::RequestSet::Lockfile.new @set, @gem_deps_file
  end

  def write_gem_deps gem_deps
    open @gem_deps_file, 'w' do |io|
      io.write gem_deps
    end
  end

  def write_lockfile lockfile
    @lock_file = File.expand_path "#{@gem_deps_file}.lock"

    open @lock_file, 'w' do |io|
      io.write lockfile
    end
  end

  def test_get
    @lockfile.instance_variable_set :@tokens, [:token]

    assert_equal :token, @lockfile.get
  end

  def test_get_type_mismatch
    @lockfile.instance_variable_set :@tokens, [[:section, 'x', 5, 1]]

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      @lockfile.get :text
    end

    expected = 'unexpected token [:section, "x"], expected :text (at 5:1)'

    assert_equal expected, e.message

    assert_equal 5, e.line
    assert_equal 1, e.column
    assert_equal File.expand_path("#{@gem_deps_file}.lock"), e.path
  end

  def test_get_type_value_mismatch
    @lockfile.instance_variable_set :@tokens, [[:section, 'x', 5, 1]]

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      @lockfile.get :section, 'y'
    end

    expected =
      'unexpected token [:section, "x"], expected [:section, "y"] (at 5:1)'

    assert_equal expected, e.message

    assert_equal 5, e.line
    assert_equal 1, e.column
    assert_equal File.expand_path("#{@gem_deps_file}.lock"), e.path
  end

  def test_parse
    write_lockfile <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    @lockfile.parse

    assert_equal [dep('a')], @set.dependencies

    assert_equal [Gem::Platform::RUBY], @lockfile.platforms

    lockfile_set = @set.sets.find do |set|
      Gem::DependencyResolver::LockSet === set
    end

    assert lockfile_set, 'could not find a LockSet'

    assert_equal %w[a-2], lockfile_set.specs.map { |tuple| tuple.full_name }
  end

  def test_peek
    @lockfile.instance_variable_set :@tokens, [:token]

    assert_equal :token, @lockfile.peek

    assert_equal :token, @lockfile.get
  end

  def test_skip
    tokens = [[:token]]

    @lockfile.instance_variable_set :@tokens, tokens

    @lockfile.skip :token

    assert_empty tokens
  end

  def test_token_pos
    assert_equal [5, 0], @lockfile.token_pos(5)

    @lockfile.instance_variable_set :@line_pos, 2
    @lockfile.instance_variable_set :@line, 1

    assert_equal [3, 1], @lockfile.token_pos(5)
  end

  def test_tokenize
    write_lockfile <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    expected = [
      [:section, 'GEM',                0, 0],
      [:newline, nil,                  3, 0],
      [:entry,   'remote',             2, 1],
      [:text,    @gem_repo,           10, 1],
      [:newline, nil,                 34, 1],
      [:entry,   'specs',              2, 2],
      [:newline, nil,                  8, 2],
      [:text,    'a',                  4, 3],
      [:l_paren, nil,                  6, 3],
      [:text,    '2',                  7, 3],
      [:r_paren, nil,                  8, 3],
      [:newline, nil,                  9, 3],
      [:newline, nil,                  0, 4],
      [:section, 'PLATFORMS',          0, 5],
      [:newline, nil,                  9, 5],
      [:text,    Gem::Platform::RUBY,  2, 6],
      [:newline, nil,                  6, 6],
      [:newline, nil,                  0, 7],
      [:section, 'DEPENDENCIES',       0, 8],
      [:newline, nil,                 12, 8],
      [:text,    'a',                  2, 9],
      [:newline, nil,                  3, 9],
    ]

    assert_equal expected, @lockfile.tokenize
  end

  def test_tokenize_conflict_markers
    write_lockfile '<<<<<<<'

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      @lockfile.tokenize
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at 0:0)",
                 e.message

    write_lockfile '|||||||'

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      @lockfile.tokenize
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at 0:0)",
                 e.message

    write_lockfile '======='

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      @lockfile.tokenize
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at 0:0)",
                 e.message

    write_lockfile '>>>>>>>'

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      @lockfile.tokenize
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at 0:0)",
                 e.message
  end

  def test_to_s_gem
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2
    end

    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_dependency
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2, 'c' => '>= 0', 'b' => '>= 0'
      fetcher.spec 'b', 2
      fetcher.spec 'c', 2
    end

    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b
      c
    b (2)
    c (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_dependency_non_default
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2, 'b' => '>= 1'
      fetcher.spec 'b', 2
    end

    @set.gem 'b'
    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b (>= 1)
    b (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
  b
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_dependency_requirement
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2, 'b' => '>= 0'
      fetcher.spec 'b', 2
    end

    @set.gem 'a', '>= 1'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b
    b (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a (>= 1)
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_path
    name, version, directory = vendor_gem

    @vendor_set.add_vendor_gem name, directory

    @set.gem 'a'

    expected = <<-LOCKFILE
PATH
  remote: #{directory}
  specs:
    #{name} (#{version})

GEM

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a!
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_path_absolute
    name, version, directory = vendor_gem

    @vendor_set.add_vendor_gem name, File.expand_path(directory)

    @set.gem 'a'

    expected = <<-LOCKFILE
PATH
  remote: #{directory}
  specs:
    #{name} (#{version})

GEM

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a!
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_platform
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2 do |spec|
        spec.platform = Gem::Platform.local
      end
    end

    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2-#{Gem::Platform.local})

PLATFORMS
  #{Gem::Platform.local}

DEPENDENCIES
  a
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_unget
    @lockfile.instance_variable_set :@current_token, :token

    @lockfile.unget

    assert_equal :token, @lockfile.get
  end

end

