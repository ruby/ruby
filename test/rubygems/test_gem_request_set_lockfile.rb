require 'rubygems/test_case'
require 'rubygems/request_set'
require 'rubygems/request_set/lockfile'

class TestGemRequestSetLockfile < Gem::TestCase

  def setup
    super

    Gem::RemoteFetcher.fetcher = @fetcher = Gem::FakeFetcher.new

    util_set_arch 'i686-darwin8.10.1'

    @set = Gem::RequestSet.new

    @git_set    = Gem::Resolver::GitSet.new
    @vendor_set = Gem::Resolver::VendorSet.new

    @set.instance_variable_set :@git_set,    @git_set
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

    expected =
      'unexpected token [:section, "x"], expected :text (at line 1 column 5)'

    assert_equal expected, e.message

    assert_equal 1, e.line
    assert_equal 5, e.column
    assert_equal File.expand_path("#{@gem_deps_file}.lock"), e.path
  end

  def test_get_type_multiple
    @lockfile.instance_variable_set :@tokens, [[:section, 'x', 5, 1]]

    assert @lockfile.get [:text, :section]
  end

  def test_get_type_value_mismatch
    @lockfile.instance_variable_set :@tokens, [[:section, 'x', 5, 1]]

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      @lockfile.get :section, 'y'
    end

    expected =
      'unexpected token [:section, "x"], expected [:section, "y"] (at line 1 column 5)'

    assert_equal expected, e.message

    assert_equal 1, e.line
    assert_equal 5, e.column
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

    @lockfile.parse

    assert_equal [dep('a')], @set.dependencies

    assert_equal [Gem::Platform::RUBY], @lockfile.platforms

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

    @lockfile.parse

    assert_equal [dep('a', '>= 1', '<= 2')], @set.dependencies

    assert_equal [Gem::Platform::RUBY], @lockfile.platforms

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    assert lockfile_set, 'could not find a LockSet'

    assert_equal %w[a-2], lockfile_set.specs.map { |tuple| tuple.full_name }
  end

  def test_parse_GIT
    write_lockfile <<-LOCKFILE
GIT
  remote: git://example/a.git
  revision: master
  specs:
    a (2)
      b (>= 3)

DEPENDENCIES
  a!
    LOCKFILE

    @lockfile.parse

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

    assert_equal [dep('b', '>= 3')], git_set.specs.values.first.dependencies
  end

  def test_parse_PATH
    _, _, directory = vendor_gem

    write_lockfile <<-LOCKFILE
PATH
  remote: #{directory}
  specs:
    a (1)

DEPENDENCIES
  a!
    LOCKFILE

    @lockfile.parse

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

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    @lockfile.parse

    assert_equal [dep('a')], @set.dependencies

    assert_equal [Gem::Platform::RUBY], @lockfile.platforms

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    assert lockfile_set, 'could not find a LockSet'

    assert_equal %w[a-2], lockfile_set.specs.map { |tuple| tuple.full_name }

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
    @lockfile.parse

    lockfile_set = @set.sets.find do |set|
      Gem::Resolver::LockSet === set
    end

    refute lockfile_set
  end

  def test_peek
    @lockfile.instance_variable_set :@tokens, [:token]

    assert_equal :token, @lockfile.peek

    assert_equal :token, @lockfile.get

    assert_equal [:EOF], @lockfile.peek
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
      b (= 2)
      c (!= 3)
      d (> 4)
      e (< 5)
      f (>= 6)
      g (<= 7)
      h (~> 8)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    expected = [
      [:section,     'GEM',                0,  0],
      [:newline,     nil,                  3,  0],

      [:entry,       'remote',             2,  1],
      [:text,        @gem_repo,           10,  1],
      [:newline,     nil,                 34,  1],

      [:entry,       'specs',              2,  2],
      [:newline,     nil,                  8,  2],

      [:text,        'a',                  4,  3],
      [:l_paren,     nil,                  6,  3],
      [:text,        '2',                  7,  3],
      [:r_paren,     nil,                  8,  3],
      [:newline,     nil,                  9,  3],

      [:text,        'b',                  6,  4],
      [:l_paren,     nil,                  8,  4],
      [:requirement, '=',                  9,  4],
      [:text,        '2',                 11,  4],
      [:r_paren,     nil,                 12,  4],
      [:newline,     nil,                 13,  4],

      [:text,        'c',                  6,  5],
      [:l_paren,     nil,                  8,  5],
      [:requirement, '!=',                 9,  5],
      [:text,        '3',                 12,  5],
      [:r_paren,     nil,                 13,  5],
      [:newline,     nil,                 14,  5],

      [:text,        'd',                  6,  6],
      [:l_paren,     nil,                  8,  6],
      [:requirement, '>',                  9,  6],
      [:text,        '4',                 11,  6],
      [:r_paren,     nil,                 12,  6],
      [:newline,     nil,                 13,  6],

      [:text,        'e',                  6,  7],
      [:l_paren,     nil,                  8,  7],
      [:requirement, '<',                  9,  7],
      [:text,        '5',                 11,  7],
      [:r_paren,     nil,                 12,  7],
      [:newline,     nil,                 13,  7],

      [:text,        'f',                  6,  8],
      [:l_paren,     nil,                  8,  8],
      [:requirement, '>=',                 9,  8],
      [:text,        '6',                 12,  8],
      [:r_paren,     nil,                 13,  8],
      [:newline,     nil,                 14,  8],

      [:text,        'g',                  6,  9],
      [:l_paren,     nil,                  8,  9],
      [:requirement, '<=',                 9,  9],
      [:text,        '7',                 12,  9],
      [:r_paren,     nil,                 13,  9],
      [:newline,     nil,                 14,  9],

      [:text,        'h',                  6, 10],
      [:l_paren,     nil,                  8, 10],
      [:requirement, '~>',                 9, 10],
      [:text,        '8',                 12, 10],
      [:r_paren,     nil,                 13, 10],
      [:newline,     nil,                 14, 10],

      [:newline,     nil,                  0, 11],

      [:section,     'PLATFORMS',          0, 12],
      [:newline,     nil,                  9, 12],

      [:text,        Gem::Platform::RUBY,  2, 13],
      [:newline,     nil,                  6, 13],

      [:newline,     nil,                  0, 14],

      [:section,     'DEPENDENCIES',       0, 15],
      [:newline,     nil,                 12, 15],

      [:text,        'a',                  2, 16],
      [:newline,     nil,                  3, 16],
    ]

    assert_equal expected, @lockfile.tokenize
  end

  def test_tokenize_capitals
    write_lockfile <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    Ab (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  Ab
    LOCKFILE

    expected = [
      [:section, 'GEM',                0, 0],
      [:newline, nil,                  3, 0],
      [:entry,   'remote',             2, 1],
      [:text,    @gem_repo,           10, 1],
      [:newline, nil,                 34, 1],
      [:entry,   'specs',              2, 2],
      [:newline, nil,                  8, 2],
      [:text,    'Ab',                 4, 3],
      [:l_paren, nil,                  7, 3],
      [:text,    '2',                  8, 3],
      [:r_paren, nil,                  9, 3],
      [:newline, nil,                 10, 3],
      [:newline, nil,                  0, 4],
      [:section, 'PLATFORMS',          0, 5],
      [:newline, nil,                  9, 5],
      [:text,    Gem::Platform::RUBY,  2, 6],
      [:newline, nil,                  6, 6],
      [:newline, nil,                  0, 7],
      [:section, 'DEPENDENCIES',       0, 8],
      [:newline, nil,                 12, 8],
      [:text,    'Ab',                 2, 9],
      [:newline, nil,                  4, 9],
    ]

    assert_equal expected, @lockfile.tokenize
  end

  def test_tokenize_conflict_markers
    write_lockfile '<<<<<<<'

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      @lockfile.tokenize
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at line 0 column 0)",
                 e.message

    write_lockfile '|||||||'

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      @lockfile.tokenize
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at line 0 column 0)",
                 e.message

    write_lockfile '======='

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      @lockfile.tokenize
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at line 0 column 0)",
                 e.message

    write_lockfile '>>>>>>>'

    e = assert_raises Gem::RequestSet::Lockfile::ParseError do
      @lockfile.tokenize
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at line 0 column 0)",
                 e.message
  end

  def test_tokenize_git
    write_lockfile <<-LOCKFILE
DEPENDENCIES
  a!
    LOCKFILE

    expected = [
      [:section, 'DEPENDENCIES',  0,  0],
      [:newline, nil,            12,  0],

      [:text,    'a',             2,  1],
      [:bang,    nil,             3,  1],
      [:newline, nil,             4,  1],
    ]

    assert_equal expected, @lockfile.tokenize
  end

  def test_tokenize_missing
    tokens = @lockfile.tokenize

    assert_empty tokens
  end

  def test_tokenize_multiple
    write_lockfile <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b (~> 3.0, >= 3.0.1)
    LOCKFILE

    expected = [
      [:section,     'GEM',      0,  0],
      [:newline,     nil,        3,  0],

      [:entry,       'remote',   2,  1],
      [:text,        @gem_repo, 10,  1],
      [:newline,     nil,       34,  1],

      [:entry,       'specs',    2,  2],
      [:newline,     nil,        8,  2],

      [:text,        'a',        4,  3],
      [:l_paren,     nil,        6,  3],
      [:text,        '2',        7,  3],
      [:r_paren,     nil,        8,  3],
      [:newline,     nil,        9,  3],

      [:text,        'b',        6,  4],
      [:l_paren,     nil,        8,  4],
      [:requirement, '~>',       9,  4],
      [:text,        '3.0',     12,  4],
      [:comma,       nil,       15,  4],
      [:requirement, '>=',      17,  4],
      [:text,        '3.0.1',   20,  4],
      [:r_paren,     nil,       25,  4],
      [:newline,     nil,       26,  4],
    ]

    assert_equal expected, @lockfile.tokenize
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
  b
  c
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
  b
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

  def test_to_s_gem_source
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2
      fetcher.clear
    end

    spec_fetcher 'http://other.example/' do |fetcher|
      fetcher.spec 'b', 2
      fetcher.clear
    end

    Gem.sources << 'http://other.example/'

    @set.gem 'a'
    @set.gem 'b'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)

GEM
  remote: http://other.example/
  specs:
    b (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
  b
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_git
    _, _, repository, = git_gem

    head = nil

    Dir.chdir repository do
      FileUtils.mkdir 'b'

      Dir.chdir 'b' do
        b = Gem::Specification.new 'b', 1 do |s|
          s.add_dependency 'a', '~> 1.0'
          s.add_dependency 'c', '~> 1.0'
        end

        open 'b.gemspec', 'w' do |io|
          io.write b.to_ruby
        end

        system @git, 'add', 'b.gemspec'
        system @git, 'commit', '--quiet', '-m', 'add b/b.gemspec'
      end

      FileUtils.mkdir 'c'

      Dir.chdir 'c' do
        c = Gem::Specification.new 'c', 1

        open 'c.gemspec', 'w' do |io|
          io.write c.to_ruby
        end

        system @git, 'add', 'c.gemspec'
        system @git, 'commit', '--quiet', '-m', 'add c/c.gemspec'
      end

      head = `#{@git} rev-parse HEAD`.strip
    end

    @git_set.add_git_gem 'a', repository, 'HEAD', true
    @git_set.add_git_gem 'b', repository, 'HEAD', true
    @git_set.add_git_gem 'c', repository, 'HEAD', true

    @set.gem 'b'

    expected = <<-LOCKFILE
GIT
  remote: #{repository}
  revision: #{head}
  specs:
    a (1)
    b (1)
      a (~> 1.0)
      c (~> 1.0)
    c (1)

PLATFORMS
  ruby

DEPENDENCIES
  a!
  b!
  c!
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_unget
    @lockfile.instance_variable_set :@current_token, :token

    @lockfile.unget

    assert_equal :token, @lockfile.get
  end

  def test_write
    @lockfile.write

    gem_deps_lock_file = "#{@gem_deps_file}.lock"

    assert_path_exists gem_deps_lock_file

    refute_empty File.read gem_deps_lock_file
  end

end

