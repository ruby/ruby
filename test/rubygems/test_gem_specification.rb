# -*- coding: us-ascii -*-
require 'rubygems/test_case'
require 'stringio'
require 'rubygems/specification'

class TestGemSpecification < Gem::TestCase

  LEGACY_YAML_SPEC = <<-EOF
--- !ruby/object:Gem::Specification
rubygems_version: "1.0"
name: keyedlist
version: !ruby/object:Gem::Version
  version: 0.4.0
date: 2004-03-28 15:37:49.828000 +02:00
platform:
summary: A Hash which automatically computes keys.
require_paths:
  - lib
files:
  - lib/keyedlist.rb
autorequire: keyedlist
author: Florian Gross
email: flgr@ccan.de
has_rdoc: true
  EOF

  LEGACY_RUBY_SPEC = <<-EOF
Gem::Specification.new do |s|
  s.name = %q{keyedlist}
  s.version = %q{0.4.0}
  s.has_rdoc = true
  s.summary = %q{A Hash which automatically computes keys.}
  s.files = [%q{lib/keyedlist.rb}]
  s.require_paths = [%q{lib}]
  s.autorequire = %q{keyedlist}
  s.author = %q{Florian Gross}
  s.email = %q{flgr@ccan.de}
end
  EOF

  def setup
    super

    @a1 = quick_spec 'a', '1' do |s|
      s.executable = 'exec'
      s.extensions << 'ext/a/extconf.rb'
      s.test_file = 'test/suite.rb'
      s.requirements << 'A working computer'
      s.rubyforge_project = 'example'
      s.license = 'MIT'

      s.add_dependency 'rake', '> 0.4'
      s.add_dependency 'jabber4r', '> 0.0.0'
      s.add_dependency 'pqa', ['> 0.4', '<= 0.6']

      s.mark_version
      s.files = %w[lib/code.rb]
    end

    @a2 = quick_spec 'a', '2' do |s|
      s.files = %w[lib/code.rb]
    end

    @current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION

    load 'rubygems/syck_hack.rb'
  end

  def test_self_attribute_names
    expected_value = %w[
      authors
      autorequire
      bindir
      cert_chain
      date
      dependencies
      description
      email
      executables
      extensions
      extra_rdoc_files
      files
      homepage
      licenses
      metadata
      name
      platform
      post_install_message
      rdoc_options
      require_paths
      required_ruby_version
      required_rubygems_version
      requirements
      rubyforge_project
      rubygems_version
      signing_key
      specification_version
      summary
      test_files
      version
    ]

    actual_value = Gem::Specification.attribute_names.map { |a| a.to_s }.sort

    assert_equal expected_value, actual_value
  end

  def test_self__load_future
    spec = Gem::Specification.new
    spec.name = 'a'
    spec.version = '1'
    spec.specification_version = @current_version + 1

    new_spec = Marshal.load Marshal.dump(spec)

    assert_equal 'a', new_spec.name
    assert_equal Gem::Version.new(1), new_spec.version
    assert_equal @current_version, new_spec.specification_version
  end

  def test_self_from_yaml
    @a1.instance_variable_set :@specification_version, nil

    spec = Gem::Specification.from_yaml @a1.to_yaml

    assert_equal Gem::Specification::NONEXISTENT_SPECIFICATION_VERSION,
                 spec.specification_version
  end

  def test_self_from_yaml_syck_date_bug
    # This is equivalent to (and totally valid) psych 1.0 output and
    # causes parse errors on syck.
    yaml = @a1.to_yaml
    yaml.sub!(/^date:.*/, "date: 2011-04-26 00:00:00.000000000Z")

    new_spec = with_syck do
      Gem::Specification.from_yaml yaml
    end

    assert_kind_of Time, @a1.date
    assert_kind_of Time, new_spec.date
  end

  def test_self_from_yaml_syck_default_key_bug
    # This is equivalent to (and totally valid) psych 1.0 output and
    # causes parse errors on syck.
    yaml = <<-YAML
--- !ruby/object:Gem::Specification
name: posix-spawn
version: !ruby/object:Gem::Version
  version: 0.3.6
  prerelease:
dependencies:
- !ruby/object:Gem::Dependency
  name: rake-compiler
  requirement: &70243867725240 !ruby/object:Gem::Requirement
    none: false
    requirements:
    - - =
      - !ruby/object:Gem::Version
        version: 0.7.6
  type: :development
  prerelease: false
  version_requirements: *70243867725240
platform: ruby
files: []
test_files: []
bindir:
    YAML

    new_spec = with_syck do
      Gem::Specification.from_yaml yaml
    end

    op = new_spec.dependencies.first.requirement.requirements.first.first
    refute_kind_of YAML::Syck::DefaultKey, op

    refute_match %r%DefaultKey%, new_spec.to_ruby
  end

  def test_self_from_yaml_cleans_up_defaultkey
    yaml = <<-YAML
--- !ruby/object:Gem::Specification
name: posix-spawn
version: !ruby/object:Gem::Version
  version: 0.3.6
  prerelease:
dependencies:
- !ruby/object:Gem::Dependency
  name: rake-compiler
  requirement: &70243867725240 !ruby/object:Gem::Requirement
    none: false
    requirements:
    - - !ruby/object:YAML::Syck::DefaultKey {}

      - !ruby/object:Gem::Version
        version: 0.7.6
  type: :development
  prerelease: false
  version_requirements: *70243867725240
platform: ruby
files: []
test_files: []
bindir:
    YAML

    new_spec = Gem::Specification.from_yaml yaml

    op = new_spec.dependencies.first.requirement.requirements.first.first
    refute_kind_of YAML::Syck::DefaultKey, op

    refute_match %r%DefaultKey%, new_spec.to_ruby
  end

  def test_self_from_yaml_cleans_up_defaultkey_from_newer_192
    yaml = <<-YAML
--- !ruby/object:Gem::Specification
name: posix-spawn
version: !ruby/object:Gem::Version
  version: 0.3.6
  prerelease:
dependencies:
- !ruby/object:Gem::Dependency
  name: rake-compiler
  requirement: &70243867725240 !ruby/object:Gem::Requirement
    none: false
    requirements:
    - - !ruby/object:Syck::DefaultKey {}

      - !ruby/object:Gem::Version
        version: 0.7.6
  type: :development
  prerelease: false
  version_requirements: *70243867725240
platform: ruby
files: []
test_files: []
bindir:
    YAML

    new_spec = Gem::Specification.from_yaml yaml

    op = new_spec.dependencies.first.requirement.requirements.first.first
    refute_kind_of YAML::Syck::DefaultKey, op

    refute_match %r%DefaultKey%, new_spec.to_ruby
  end

  def test_self_from_yaml_cleans_up_Date_objects
    yaml = <<-YAML
--- !ruby/object:Gem::Specification
rubygems_version: 0.8.1
specification_version: 1
name: diff-lcs
version: !ruby/object:Gem::Version
  version: 1.1.2
date: 2004-10-20
summary: Provides a list of changes that represent the difference between two sequenced collections.
require_paths:
  - lib
author: Austin Ziegler
email: diff-lcs@halostatue.ca
homepage: http://rubyforge.org/projects/ruwiki/
rubyforge_project: ruwiki
description: "Test"
bindir: bin
has_rdoc: true
required_ruby_version: !ruby/object:Gem::Version::Requirement
  requirements:
    -
      - ">="
      - !ruby/object:Gem::Version
        version: 1.8.1
  version:
platform: ruby
files:
  - tests/00test.rb
rdoc_options:
  - "--title"
  - "Diff::LCS -- A Diff Algorithm"
  - "--main"
  - README
  - "--line-numbers"
extra_rdoc_files:
  - README
  - ChangeLog
  - Install
executables:
  - ldiff
  - htmldiff
extensions: []
requirements: []
dependencies: []
    YAML

    new_spec = Gem::Specification.from_yaml yaml

    assert_kind_of Time, new_spec.date
  end

  def test_self_load
    full_path = @a2.spec_file
    write_file full_path do |io|
      io.write @a2.to_ruby_for_cache
    end

    spec = Gem::Specification.load full_path

    @a2.files.clear

    assert_equal @a2, spec
  end

  def test_self_load_tainted
    full_path = @a2.spec_file
    write_file full_path do |io|
      io.write @a2.to_ruby_for_cache
    end

    full_path.taint
    loader = Thread.new { $SAFE = 1; Gem::Specification.load full_path }
    spec = loader.value

    @a2.files.clear

    assert_equal @a2, spec
  end

  def test_self_load_escape_curly
    @a2.name = 'a};raise "improper escaping";%q{'

    full_path = @a2.spec_file
    write_file full_path do |io|
      io.write @a2.to_ruby_for_cache
    end

    spec = Gem::Specification.load full_path

    @a2.files.clear

    assert_equal @a2, spec
  end

  def test_self_load_escape_interpolation
    @a2.name = 'a#{raise %<improper escaping>}'

    full_path = @a2.spec_file
    write_file full_path do |io|
      io.write @a2.to_ruby_for_cache
    end

    spec = Gem::Specification.load full_path

    @a2.files.clear

    assert_equal @a2, spec
  end

  def test_self_load_escape_quote
    @a2.name = 'a";raise "improper escaping";"'

    full_path = @a2.spec_file
    write_file full_path do |io|
      io.write @a2.to_ruby_for_cache
    end

    spec = Gem::Specification.load full_path

    @a2.files.clear

    assert_equal @a2, spec
  end

  if defined?(Encoding)
  def test_self_load_utf8_with_ascii_encoding
    int_enc = Encoding.default_internal
    silence_warnings { Encoding.default_internal = 'US-ASCII' }

    spec2 = @a2.dup
    bin = "\u5678"
    spec2.authors = [bin]
    full_path = spec2.spec_file
    write_file full_path do |io|
      io.write spec2.to_ruby_for_cache.force_encoding('BINARY').sub("\\u{5678}", bin.force_encoding('BINARY'))
    end

    spec = Gem::Specification.load full_path

    spec2.files.clear

    assert_equal spec2, spec
  ensure
    silence_warnings { Encoding.default_internal = int_enc }
  end
  end

  def test_self_load_legacy_ruby
    spec = Gem::Deprecate.skip_during do
      eval LEGACY_RUBY_SPEC
    end
    assert_equal 'keyedlist', spec.name
    assert_equal '0.4.0', spec.version.to_s
    assert_equal Gem::Specification::TODAY, spec.date
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new('1'))
    assert_equal false, spec.has_unit_tests?
  end

  def test_self_normalize_yaml_input_with_183_yaml
    input = "!ruby/object:Gem::Specification "
    assert_equal "--- #{input}", Gem::Specification.normalize_yaml_input(input)
  end

  def test_self_normalize_yaml_input_with_non_183_yaml
    input = "--- !ruby/object:Gem::Specification "
    assert_equal input, Gem::Specification.normalize_yaml_input(input)
  end

  def test_self_normalize_yaml_input_with_183_io
    input = "!ruby/object:Gem::Specification "
    assert_equal "--- #{input}",
      Gem::Specification.normalize_yaml_input(StringIO.new(input))
  end

  def test_self_normalize_yaml_input_with_non_183_io
    input = "--- !ruby/object:Gem::Specification "
    assert_equal input,
      Gem::Specification.normalize_yaml_input(StringIO.new(input))
  end

  def test_self_normalize_yaml_input_with_192_yaml
    input = "--- !ruby/object:Gem::Specification \nblah: !!null \n"
    expected = "--- !ruby/object:Gem::Specification \nblah: \n"

    assert_equal expected, Gem::Specification.normalize_yaml_input(input)
  end

  DATA_PATH = File.expand_path "../data", __FILE__

  def test_handles_private_null_type
    path = File.join DATA_PATH, "null-type.gemspec.rz"

    data = Marshal.load Gem.inflate(Gem.read_binary(path))

    assert_equal nil, data.rubyforge_project
  end

  def test_emits_zulu_timestamps_properly
    t = Time.utc(2012, 3, 12)
    @a2.date = t

    yaml = with_psych { @a2.to_yaml }

    assert_match %r!date: 2012-03-12 00:00:00\.000000000 Z!, yaml
  end if RUBY_VERSION =~ /1\.9\.2/

  def test_initialize
    spec = Gem::Specification.new do |s|
      s.name = "blah"
      s.version = "1.3.5"
    end

    assert_equal "blah", spec.name
    assert_equal "1.3.5", spec.version.to_s
    assert_equal Gem::Platform::RUBY, spec.platform
    assert_equal nil, spec.summary
    assert_equal [], spec.files

    assert_equal [], spec.test_files
    assert_equal [], spec.rdoc_options
    assert_equal [], spec.extra_rdoc_files
    assert_equal [], spec.executables
    assert_equal [], spec.extensions
    assert_equal [], spec.requirements
    assert_equal [], spec.dependencies
    assert_equal 'bin', spec.bindir
    assert_equal '>= 0', spec.required_ruby_version.to_s
    assert_equal '>= 0', spec.required_rubygems_version.to_s
  end

  def test_initialize_future
    version = Gem::Specification::CURRENT_SPECIFICATION_VERSION + 1
    spec = Gem::Specification.new do |s|
      s.name = "blah"
      s.version = "1.3.5"

      s.specification_version = version

      s.new_unknown_attribute = "a value"
    end

    assert_equal "blah", spec.name
    assert_equal "1.3.5", spec.version.to_s
  end

  def test_initialize_copy
    spec = Gem::Specification.new do |s|
      s.name = "blah"
      s.version = "1.3.5"
      s.summary = 'summary'
      s.description = 'description'
      s.authors = 'author a', 'author b'
      s.licenses = 'BSD'
      s.files = 'lib/file.rb'
      s.test_files = 'test/file.rb'
      s.rdoc_options = '--foo'
      s.extra_rdoc_files = 'README.txt'
      s.executables = 'exec'
      s.extensions = 'ext/extconf.rb'
      s.requirements = 'requirement'
      s.add_dependency 'some_gem'
    end

    new_spec = spec.dup

    assert_equal "blah", spec.name
    assert_same  spec.name, new_spec.name

    assert_equal "1.3.5", spec.version.to_s
    assert_same spec.version, new_spec.version

    assert_equal Gem::Platform::RUBY, spec.platform
    assert_same spec.platform, new_spec.platform

    assert_equal 'summary', spec.summary
    assert_same spec.summary, new_spec.summary

    assert_equal %w[lib/file.rb test/file.rb bin/exec README.txt
                    ext/extconf.rb],
                 spec.files
    refute_same spec.files, new_spec.files, 'files'

    assert_equal %w[test/file.rb], spec.test_files
    refute_same spec.test_files, new_spec.test_files, 'test_files'

    assert_equal %w[--foo], spec.rdoc_options
    refute_same spec.rdoc_options, new_spec.rdoc_options, 'rdoc_options'

    assert_equal %w[README.txt], spec.extra_rdoc_files
    refute_same spec.extra_rdoc_files, new_spec.extra_rdoc_files,
                'extra_rdoc_files'

    assert_equal %w[exec], spec.executables
    refute_same spec.executables, new_spec.executables, 'executables'

    assert_equal %w[ext/extconf.rb], spec.extensions
    refute_same spec.extensions, new_spec.extensions, 'extensions'

    assert_equal %w[requirement], spec.requirements
    refute_same spec.requirements, new_spec.requirements, 'requirements'

    assert_equal [Gem::Dependency.new('some_gem', Gem::Requirement.default)],
                 spec.dependencies
    refute_same spec.dependencies, new_spec.dependencies, 'dependencies'

    assert_equal 'bin', spec.bindir
    assert_same spec.bindir, new_spec.bindir

    assert_equal '>= 0', spec.required_ruby_version.to_s
    assert_same spec.required_ruby_version, new_spec.required_ruby_version

    assert_equal '>= 0', spec.required_rubygems_version.to_s
    assert_same spec.required_rubygems_version,
                new_spec.required_rubygems_version
  end

  def test_initialize_copy_broken
    spec = Gem::Specification.new do |s|
      s.name = 'a'
      s.version = '1'
    end

    spec.instance_variable_set :@licenses, :blah
    spec.loaded_from = '/path/to/file'

    e = assert_raises Gem::FormatException do
      spec.dup
    end

    assert_equal 'a-1 has an invalid value for @licenses', e.message
    assert_equal '/path/to/file', e.file_path
  end

  def test__dump
    @a2.platform = Gem::Platform.local
    @a2.instance_variable_set :@original_platform, 'old_platform'

    data = Marshal.dump @a2

    same_spec = Marshal.load data

    assert_equal 'old_platform', same_spec.original_platform
  end

  def test_activate
    @a2.activate

    assert @a2.activated?
  end

  def test_add_dependency_with_explicit_type
    gem = quick_spec "awesome", "1.0" do |awesome|
      awesome.add_development_dependency "monkey"
    end

    monkey = gem.dependencies.detect { |d| d.name == "monkey" }
    assert_equal(:development, monkey.type)
  end

  def test_author
    assert_equal 'A User', @a1.author
  end

  def test_authors
    assert_equal ['A User'], @a1.authors
  end

  def test_bindir_equals
    @a1.bindir = 'apps'

    assert_equal 'apps', @a1.bindir
  end

  def test_bindir_equals_nil
    @a2.bindir = nil
    @a2.executable = 'app'

    assert_equal nil, @a2.bindir
    assert_equal %w[lib/code.rb app], @a2.files
  end

  def test_date
    assert_equal Gem::Specification::TODAY, @a1.date
  end

  def test_date_equals_date
    @a1.date = Date.new(2003, 9, 17)
    assert_equal Time.utc(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_string
    @a1.date = '2003-09-17'
    assert_equal Time.utc(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_string_bad
    assert_raises Gem::InvalidSpecificationException do
      @a1.date = '9/11/2003'
    end
  end

  def test_date_equals_time
    @a1.date = Time.local(2003, 9, 17, 0,0,0)
    assert_equal Time.utc(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_time_local
    @a1.date = Time.local(2003, 9, 17, 19,50,0) # may not pass in utc >= +4
    assert_equal Time.utc(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_time_utc
    @a1.date = Time.utc(2003, 9, 17, 19,50,0)
    assert_equal Time.utc(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_tolerates_hour_sec_zulu
    @a1.date = "2012-01-12 11:22:33.4444444 Z"
    assert_equal Time.utc(2012,01,12,0,0,0), @a1.date
  end

  def test_date_tolerates_hour_sec_and_timezone
    @a1.date = "2012-01-12 11:22:33.4444444 +02:33"
    assert_equal Time.utc(2012,01,12,0,0,0), @a1.date
  end

  def test_dependencies
    util_setup_deps
    assert_equal [@bonobo, @monkey], @gem.dependencies
  end

  def test_doc_dir
    assert_equal File.join(@gemhome, 'doc', 'a-1'), @a1.doc_dir
  end

  def test_doc_dir_type
    assert_equal File.join(@gemhome, 'doc', 'a-1', 'ri'), @a1.doc_dir('ri')
  end

  def test_runtime_dependencies
    util_setup_deps
    assert_equal [@bonobo], @gem.runtime_dependencies
  end

  def test_development_dependencies
    util_setup_deps
    assert_equal [@monkey], @gem.development_dependencies
  end

  def test_description
    assert_equal 'This is a test description', @a1.description
  end

  def test_eql_eh
    g1 = new_spec 'gem', 1
    g2 = new_spec 'gem', 1

    assert_equal g1, g2
    assert_equal g1.hash, g2.hash
    assert_equal true, g1.eql?(g2)
  end

  def test_eql_eh_extensions
    spec = @a1.dup
    spec.extensions = 'xx'

    refute_operator @a1, :eql?, spec
    refute_operator spec, :eql?, @a1
  end

  def test_executables
    @a1.executable = 'app'
    assert_equal %w[app], @a1.executables
  end

  def test_executable_equals
    @a2.executable = 'app'
    assert_equal 'app', @a2.executable
    assert_equal %w[lib/code.rb bin/app], @a2.files
  end

  def test_extensions
    assert_equal ['ext/a/extconf.rb'], @a1.extensions
  end

  def test_files
    @a1.files = %w(files bin/common)
    @a1.test_files = %w(test_files bin/common)
    @a1.executables = %w(executables common)
    @a1.extra_rdoc_files = %w(extra_rdoc_files bin/common)
    @a1.extensions = %w(extensions bin/common)

    expected = %w[
      bin/common
      bin/executables
      extensions
      extra_rdoc_files
      files
      test_files
    ]
    assert_equal expected, @a1.files.sort
  end

  def test_files_append
    @a1.files            = %w(files bin/common)
    @a1.test_files       = %w(test_files bin/common)
    @a1.executables      = %w(executables common)
    @a1.extra_rdoc_files = %w(extra_rdoc_files bin/common)
    @a1.extensions       = %w(extensions bin/common)

    expected = %w[
      bin/common
      bin/executables
      extensions
      extra_rdoc_files
      files
      test_files
    ]
    assert_equal expected, @a1.files.sort

    @a1.files << "generated_file.c"

    expected << "generated_file.c"
    expected.sort!

    assert_equal expected, @a1.files.sort
  end

  def test_files_duplicate
    @a2.files = %w[a b c d b]
    @a2.extra_rdoc_files = %w[x y z x]
    @a2.normalize

    assert_equal %w[a b c d x y z], @a2.files
    assert_equal %w[x y z], @a2.extra_rdoc_files
  end

  def test_files_extra_rdoc_files
    @a2.files = %w[a b c d]
    @a2.extra_rdoc_files = %w[x y z]
    @a2.normalize
    assert_equal %w[a b c d x y z], @a2.files
  end

  def test_files_non_array
    @a1.files = "F"
    @a1.test_files = "TF"
    @a1.executables = "X"
    @a1.extra_rdoc_files = "ERF"
    @a1.extensions = "E"

    assert_equal %w[E ERF F TF bin/X], @a1.files.sort
  end

  def test_files_non_array_pathological
    @a1.instance_variable_set :@files, "F"
    @a1.instance_variable_set :@test_files, "TF"
    @a1.instance_variable_set :@extra_rdoc_files, "ERF"
    @a1.instance_variable_set :@extensions, "E"
    @a1.instance_variable_set :@executables, "X"

    assert_equal %w[E ERF F TF bin/X], @a1.files.sort
    assert_kind_of Integer, @a1.hash
  end

  def test_for_cache
    @a2.add_runtime_dependency 'b', '1'
    @a2.dependencies.first.instance_variable_set :@type, nil
    @a2.required_rubygems_version = Gem::Requirement.new '> 0'
    @a2.test_files = %w[test/test_b.rb]

    refute_empty @a2.files
    refute_empty @a2.test_files

    spec = @a2.for_cache

    assert_empty spec.files
    assert_empty spec.test_files

    refute_empty @a2.files
    refute_empty @a2.test_files
  end

  def test_full_gem_path
    assert_equal File.join(@gemhome, 'gems', @a1.full_name), @a1.full_gem_path

    @a1.original_platform = 'mswin32'

    assert_equal File.join(@gemhome, 'gems', @a1.original_name),
                 @a1.full_gem_path
  end

  def test_full_gem_path_double_slash
    gemhome = @gemhome.to_s.sub(/\w\//, '\&/')
    @a1.loaded_from = File.join gemhome, "specifications", @a1.spec_name

    expected = File.join @gemhome, "gems", @a1.full_name
    assert_equal expected, @a1.full_gem_path
  end

  def test_full_name
    assert_equal 'a-1', @a1.full_name

    @a1 = Gem::Specification.new "a", 1
    @a1.platform = Gem::Platform.new ['universal', 'darwin', nil]
    assert_equal 'a-1-universal-darwin', @a1.full_name

    @a1 = Gem::Specification.new "a", 1
    @a1.instance_variable_set :@new_platform, 'mswin32'
    assert_equal 'a-1-mswin32', @a1.full_name, 'legacy'

    return if win_platform?

    @a1 = Gem::Specification.new "a", 1
    @a1.platform = 'current'
    assert_equal 'a-1-x86-darwin-8', @a1.full_name
  end

  def test_full_name_windows
    test_cases = {
      'i386-mswin32'      => 'a-1-x86-mswin32-60',
      'i386-mswin32_80'   => 'a-1-x86-mswin32-80',
      'i386-mingw32'      => 'a-1-x86-mingw32'
    }

    test_cases.each do |arch, expected|
      @a1 = Gem::Specification.new "a", 1
      util_set_arch arch
      @a1.platform = 'current'
      assert_equal expected, @a1.full_name
    end
  end

  def test_hash
    assert_equal @a1.hash, @a1.hash
    assert_equal @a1.hash, @a1.dup.hash
    refute_equal @a1.hash, @a2.hash
  end

  def test_base_dir
    assert_equal @gemhome, @a1.base_dir
  end

  def test_base_dir_not_loaded
    @a1.instance_variable_set :@loaded_from, nil

    assert_equal Gem.dir, @a1.base_dir
  end

  def test_base_dir_default
    default_dir =
      File.join Gem::Specification.default_specifications_dir, @a1.spec_name

    @a1.instance_variable_set :@loaded_from, default_dir

    assert_equal Gem.default_dir, @a1.base_dir
  end

  def test_lib_files
    @a1.files = %w[lib/foo.rb Rakefile]

    assert_equal %w[lib/foo.rb], @a1.lib_files
  end

  def test_license
    assert_equal 'MIT', @a1.license
  end

  def test_licenses
    assert_equal ['MIT'], @a1.licenses
  end

  def test_name
    assert_equal 'a', @a1.name
  end

  def test_original_name
    assert_equal 'a-1', @a1.full_name

    @a1.platform = 'i386-linux'
    @a1.instance_variable_set :@original_platform, 'i386-linux'
    assert_equal 'a-1-i386-linux', @a1.original_name
  end

  def test_platform
    assert_equal Gem::Platform::RUBY, @a1.platform
  end

  def test_platform_change_reset_full_name
    orig_full_name = @a1.full_name

    @a1.platform = "universal-unknown"
    refute_equal orig_full_name, @a1.full_name
  end

  def test_platform_change_reset_cache_file
    orig_cache_file = @a1.cache_file

    @a1.platform = "universal-unknown"
    refute_equal orig_cache_file, @a1.cache_file
  end

  def test_platform_equals
    @a1.platform = nil
    assert_equal Gem::Platform::RUBY, @a1.platform

    @a1.platform = Gem::Platform::RUBY
    assert_equal Gem::Platform::RUBY, @a1.platform

    test_cases = {
      'i386-mswin32'    => ['x86', 'mswin32', '60'],
      'i386-mswin32_80' => ['x86', 'mswin32', '80'],
      'i386-mingw32'    => ['x86', 'mingw32', nil ],
      'x86-darwin8'     => ['x86', 'darwin',  '8' ],
    }

    test_cases.each do |arch, expected|
      util_set_arch arch
      @a1.platform = Gem::Platform::CURRENT
      assert_equal Gem::Platform.new(expected), @a1.platform
    end
  end

  def test_platform_equals_current
    @a1.platform = Gem::Platform::CURRENT
    assert_equal Gem::Platform.local, @a1.platform
    assert_equal Gem::Platform.local.to_s, @a1.original_platform
  end

  def test_platform_equals_legacy
    @a1.platform = 'mswin32'
    assert_equal Gem::Platform.new('x86-mswin32'), @a1.platform

    @a1.platform = 'i586-linux'
    assert_equal Gem::Platform.new('x86-linux'), @a1.platform

    @a1.platform = 'powerpc-darwin'
    assert_equal Gem::Platform.new('ppc-darwin'), @a1.platform
  end

  def test_prerelease_spec_adds_required_rubygems_version
    @prerelease = quick_spec('tardis', '2.2.0.a')
    refute @prerelease.required_rubygems_version.satisfied_by?(Gem::Version.new('1.3.1'))
    assert @prerelease.required_rubygems_version.satisfied_by?(Gem::Version.new('1.4.0'))
  end

  def test_require_paths
    @a1.require_path = 'lib'
    assert_equal %w[lib], @a1.require_paths
  end

  def test_requirements
    assert_equal ['A working computer'], @a1.requirements
  end

  def test_runtime_dependencies_legacy
    # legacy gems don't have a type
    @a1.runtime_dependencies.each do |dep|
      dep.instance_variable_set :@type, nil
    end

    expected = %w[rake jabber4r pqa]

    assert_equal expected, @a1.runtime_dependencies.map { |d| d.name }
  end

  def test_spaceship_name
    s1 = new_spec 'a', '1'
    s2 = new_spec 'b', '1'

    assert_equal(-1, (s1 <=> s2))
    assert_equal( 0, (s1 <=> s1))
    assert_equal( 1, (s2 <=> s1))
  end

  def test_spaceship_platform
    s1 = new_spec 'a', '1'
    s2 = new_spec 'a', '1' do |s|
      s.platform = Gem::Platform.new 'x86-my_platform1'
    end

    assert_equal( -1, (s1 <=> s2))
    assert_equal(  0, (s1 <=> s1))
    assert_equal(  1, (s2 <=> s1))
  end

  def test_spaceship_version
    s1 = new_spec 'a', '1'
    s2 = new_spec 'a', '2'

    assert_equal( -1, (s1 <=> s2))
    assert_equal(  0, (s1 <=> s1))
    assert_equal(  1, (s2 <=> s1))
  end

  def test_spec_file
    assert_equal File.join(@gemhome, 'specifications', 'a-1.gemspec'),
                 @a1.spec_file
  end

  def test_spec_name
    assert_equal 'a-1.gemspec', @a1.spec_name
  end

  def test_summary
    assert_equal 'this is a summary', @a1.summary
  end

  def test_test_files
    @a1.test_file = 'test/suite.rb'
    assert_equal ['test/suite.rb'], @a1.test_files
  end

  def test_to_ruby
    @a2.add_runtime_dependency 'b', '1'
    @a2.dependencies.first.instance_variable_set :@type, nil
    @a2.required_rubygems_version = Gem::Requirement.new '> 0'

    ruby_code = @a2.to_ruby

    expected = <<-SPEC
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "a"
  s.version = "2"

  s.required_rubygems_version = Gem::Requirement.new(\"> 0\") if s.respond_to? :required_rubygems_version=
  s.authors = ["A User"]
  s.date = "#{Gem::Specification::TODAY.strftime "%Y-%m-%d"}"
  s.description = "This is a test description"
  s.email = "example@example.com"
  s.files = ["lib/code.rb"]
  s.homepage = "http://example.com"
  s.require_paths = ["lib"]
  s.rubygems_version = "#{Gem::VERSION}"
  s.summary = "this is a summary"

  if s.respond_to? :specification_version then
    s.specification_version = #{Gem::Specification::CURRENT_SPECIFICATION_VERSION}

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<b>, [\"= 1\"])
    else
      s.add_dependency(%q<b>, [\"= 1\"])
    end
  else
    s.add_dependency(%q<b>, [\"= 1\"])
  end
end
    SPEC

    assert_equal expected, ruby_code

    same_spec = eval ruby_code

    assert_equal @a2, same_spec
  end

  def test_to_ruby_for_cache
    @a2.add_runtime_dependency 'b', '1'
    @a2.dependencies.first.instance_variable_set :@type, nil
    @a2.required_rubygems_version = Gem::Requirement.new '> 0'

    # cached specs do not have spec.files populated:
    ruby_code = @a2.to_ruby_for_cache

    expected = <<-SPEC
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "a"
  s.version = "2"

  s.required_rubygems_version = Gem::Requirement.new(\"> 0\") if s.respond_to? :required_rubygems_version=
  s.authors = ["A User"]
  s.date = "#{Gem::Specification::TODAY.strftime "%Y-%m-%d"}"
  s.description = "This is a test description"
  s.email = "example@example.com"
  s.homepage = "http://example.com"
  s.require_paths = ["lib"]
  s.rubygems_version = "#{Gem::VERSION}"
  s.summary = "this is a summary"

  if s.respond_to? :specification_version then
    s.specification_version = #{Gem::Specification::CURRENT_SPECIFICATION_VERSION}

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<b>, [\"= 1\"])
    else
      s.add_dependency(%q<b>, [\"= 1\"])
    end
  else
    s.add_dependency(%q<b>, [\"= 1\"])
  end
end
    SPEC

    assert_equal expected, ruby_code

    same_spec = eval ruby_code

    # cached specs do not have spec.files populated:
    @a2.files = []
    assert_equal @a2, same_spec
  end

  def test_to_ruby_fancy
    @a1.platform = Gem::Platform.local
    ruby_code = @a1.to_ruby

    local = Gem::Platform.local
    expected_platform = "[#{local.cpu.inspect}, #{local.os.inspect}, #{local.version.inspect}]"

    expected = <<-SPEC
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "a"
  s.version = "1"
  s.platform = Gem::Platform.new(#{expected_platform})

  s.required_rubygems_version = Gem::Requirement.new(\">= 0\") if s.respond_to? :required_rubygems_version=
  s.authors = ["A User"]
  s.date = "#{Gem::Specification::TODAY.strftime "%Y-%m-%d"}"
  s.description = "This is a test description"
  s.email = "example@example.com"
  s.executables = ["exec"]
  s.extensions = ["ext/a/extconf.rb"]
  s.files = ["lib/code.rb", "test/suite.rb", "bin/exec", "ext/a/extconf.rb"]
  s.homepage = "http://example.com"
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.requirements = ["A working computer"]
  s.rubyforge_project = "example"
  s.rubygems_version = "#{Gem::VERSION}"
  s.summary = "this is a summary"
  s.test_files = ["test/suite.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<rake>, [\"> 0.4\"])
      s.add_runtime_dependency(%q<jabber4r>, [\"> 0.0.0\"])
      s.add_runtime_dependency(%q<pqa>, [\"<= 0.6\", \"> 0.4\"])
    else
      s.add_dependency(%q<rake>, [\"> 0.4\"])
      s.add_dependency(%q<jabber4r>, [\"> 0.0.0\"])
      s.add_dependency(%q<pqa>, [\"<= 0.6\", \"> 0.4\"])
    end
  else
    s.add_dependency(%q<rake>, [\"> 0.4\"])
    s.add_dependency(%q<jabber4r>, [\"> 0.0.0\"])
    s.add_dependency(%q<pqa>, [\"<= 0.6\", \"> 0.4\"])
  end
end
    SPEC

    assert_equal expected, ruby_code

    same_spec = eval ruby_code

    assert_equal @a1, same_spec
  end

  def test_to_ruby_legacy
    gemspec1 = Gem::Deprecate.skip_during do
      eval LEGACY_RUBY_SPEC
    end
    ruby_code = gemspec1.to_ruby
    gemspec2 = eval ruby_code

    assert_equal gemspec1, gemspec2
  end

  def test_to_ruby_nested_hash
    metadata = {}
    metadata[metadata] = metadata

    @a2.metadata = metadata

    ruby = @a2.to_ruby

    assert_match %r%^  s\.metadata = \{ "%, ruby
  end

  def test_to_ruby_platform
    @a2.platform = Gem::Platform.local
    @a2.instance_variable_set :@original_platform, 'old_platform'

    ruby_code = @a2.to_ruby

    same_spec = eval ruby_code

    assert_equal 'old_platform', same_spec.original_platform
  end

  def test_to_yaml
    yaml_str = @a1.to_yaml

    refute_match '!!null', yaml_str

    same_spec = Gem::Specification.from_yaml(yaml_str)

    assert_equal @a1, same_spec
  end

  def test_to_yaml_fancy
    @a1.platform = Gem::Platform.local
    yaml_str = @a1.to_yaml

    same_spec = Gem::Specification.from_yaml(yaml_str)

    assert_equal Gem::Platform.local, same_spec.platform

    assert_equal @a1, same_spec
  end

  def test_to_yaml_platform_empty_string
    @a1.instance_variable_set :@original_platform, ''

    assert_match %r|^platform: ruby$|, @a1.to_yaml
  end

  def test_to_yaml_platform_legacy
    @a1.platform = 'powerpc-darwin7.9.0'
    @a1.instance_variable_set :@original_platform, 'powerpc-darwin7.9.0'

    yaml_str = @a1.to_yaml

    same_spec = YAML.load yaml_str

    assert_equal Gem::Platform.new('powerpc-darwin7'), same_spec.platform
    assert_equal 'powerpc-darwin7.9.0', same_spec.original_platform
  end

  def test_to_yaml_platform_nil
    @a1.instance_variable_set :@original_platform, nil

    assert_match %r|^platform: ruby$|, @a1.to_yaml
  end

  def test_validate
    util_setup_validate

    Dir.chdir @tempdir do
      assert @a1.validate
    end
  end

  def x s; s.gsub(/xxx/, ''); end
  def w; x "WARxxxNING"; end
  def t; x "TOxxxDO"; end
  def f; x "FxxxIXME"; end

  def test_validate_authors
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.authors = [""]

      use_ui @ui do
        @a1.validate
      end

      assert_equal "#{w}:  no author specified\n", @ui.error, 'error'

      @a1.authors = [Object.new]

      assert_equal [], @a1.authors

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal "authors may not be empty", e.message

      @a1.authors = ["#{f} (who is writing this software)"]

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %{"#{f}" or "#{t}" is not an author}, e.message

      @a1.authors = ["#{t} (who is writing this software)"]

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %{"#{f}" or "#{t}" is not an author}, e.message
    end
  end

  def test_validate_autorequire
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.autorequire = 'code'

      use_ui @ui do
        @a1.validate
      end

      assert_equal "#{w}:  deprecated autorequire specified\n",
                   @ui.error, 'error'
    end
  end

  def test_validate_dependencies
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.add_runtime_dependency     'b', '>= 1.0.rc1'
      @a1.add_development_dependency 'c', '>= 2.0.rc2'

      use_ui @ui do
        @a1.validate
      end

      expected = <<-EXPECTED
#{w}:  prerelease dependency on b (>= 1.0.rc1) is not recommended
#{w}:  prerelease dependency on c (>= 2.0.rc2, development) is not recommended
      EXPECTED

      assert_equal expected, @ui.error, 'warning'
    end
  end

  def test_validate_description
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.description = ''

      use_ui @ui do
        @a1.validate
      end

      assert_equal "#{w}:  no description specified\n", @ui.error, "error"

      @ui = Gem::MockGemUi.new
      @a1.summary = "this is my summary"
      @a1.description = @a1.summary

      use_ui @ui do
        @a1.validate
      end

      assert_equal "#{w}:  description and summary are identical\n",
                   @ui.error, "error"

      @a1.description = "#{f} (describe your package)"

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %{"#{f}" or "#{t}" is not a description}, e.message

      @a1.description = "#{t} (describe your package)"

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %{"#{f}" or "#{t}" is not a description}, e.message
    end
  end

  def test_validate_email
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.email = ""

      use_ui @ui do
        @a1.validate
      end

      assert_equal "#{w}:  no email specified\n", @ui.error, "error"

      @a1.email = "FIxxxXME (your e-mail)".sub(/xxx/, "")

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %{"#{f}" or "#{t}" is not an email}, e.message

      @a1.email = "#{t} (your e-mail)"

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %{"#{f}" or "#{t}" is not an email}, e.message
    end
  end

  def test_validate_empty
    e = assert_raises Gem::InvalidSpecificationException do
      Gem::Specification.new.validate
    end

    assert_equal 'missing value for attribute name', e.message
  end

  def test_validate_executables
    util_setup_validate

    FileUtils.mkdir_p File.join(@tempdir, 'bin')
    File.open File.join(@tempdir, 'bin', 'exec'), 'w' do end
    FileUtils.mkdir_p File.join(@tempdir, 'exec')

    use_ui @ui do
      Dir.chdir @tempdir do
        assert @a1.validate
      end
    end

    assert_equal %w[exec], @a1.executables

    assert_equal '', @ui.output, 'output'
    assert_equal "#{w}:  bin/exec is missing #! line\n", @ui.error, 'error'
  end

  def test_validate_empty_require_paths
    if win_platform? then
      skip 'test_validate_empty_require_paths skipped on MS Windows (symlink)'
    else
      util_setup_validate

      @a1.require_paths = []
      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal 'specification must have at least one require_path',
                   e.message
    end
  end

  def test_validate_files
    skip 'test_validate_files skipped on MS Windows (symlink)' if win_platform?
    util_setup_validate

    @a1.files += ['lib', 'lib2']

    Dir.chdir @tempdir do
      FileUtils.ln_s '/root/path', 'lib2' unless vc_windows?

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal '["lib2"] are not files', e.message
    end

    assert_equal %w[lib/code.rb test/suite.rb bin/exec ext/a/extconf.rb lib2],
                 @a1.files
  end

  def test_validate_homepage
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.homepage = nil

      use_ui @ui do
        @a1.validate
      end

      assert_equal "#{w}:  no homepage specified\n", @ui.error, 'error'

      @ui = Gem::MockGemUi.new

      @a1.homepage = ''

      use_ui @ui do
        @a1.validate
      end

      assert_equal "#{w}:  no homepage specified\n", @ui.error, 'error'

      @a1.homepage = 'over at my cool site'

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal '"over at my cool site" is not a URI', e.message
    end
  end

  def test_validate_name
    util_setup_validate

    e = assert_raises Gem::InvalidSpecificationException do
      @a1.name = :json
      @a1.validate
    end

    assert_equal 'invalid value for attribute name: ":json"', e.message
  end

  def test_validate_non_nil
    util_setup_validate

    Dir.chdir @tempdir do
      assert @a1.validate

      Gem::Specification.non_nil_attributes.each do |name|
        next if name == :files # set by #normalize
        spec = @a1.dup
        spec.instance_variable_set "@#{name}", nil

        e = assert_raises Gem::InvalidSpecificationException do
          spec.validate
        end

        assert_match %r%^#{name}%, e.message
      end
    end
  end

  def test_validate_permissions
    skip 'chmod not supported' if Gem.win_platform?

    util_setup_validate

    Dir.chdir @tempdir do
      File.chmod 0640, File.join('lib', 'code.rb')
      File.chmod 0640, File.join('bin', 'exec')

      use_ui @ui do
        @a1.validate
      end

      assert_match "#{w}:  lib/code.rb is not world-readable\n", @ui.error
      assert_match "#{w}:  bin/exec is not world-readable\n", @ui.error
      assert_match "#{w}:  bin/exec is not executable\n", @ui.error
    end
  end

  def test_validate_platform_legacy
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.platform = 'mswin32'
      assert @a1.validate

      @a1.platform = 'i586-linux'
      assert @a1.validate

      @a1.platform = 'powerpc-darwin'
      assert @a1.validate
    end
  end

  def test_validate_rubygems_version
    util_setup_validate

    @a1.rubygems_version = "3"
    e = assert_raises Gem::InvalidSpecificationException do
      @a1.validate
    end

    assert_equal "expected RubyGems version #{Gem::VERSION}, was 3",
                 e.message
  end

  def test_validate_specification_version
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.specification_version = '1.0'

      e = assert_raises Gem::InvalidSpecificationException do
        use_ui @ui do
          @a1.validate
        end
      end

      err = 'specification_version must be a Fixnum (did you mean version?)'
      assert_equal err, e.message
    end
  end

  def test_validate_summary
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.summary = ''

      use_ui @ui do
        @a1.validate
      end

      assert_equal "#{w}:  no summary specified\n", @ui.error, 'error'

      @a1.summary = "#{f} (describe your package)"

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %{"#{f}" or "#{t}" is not a summary}, e.message

      @a1.summary = "#{t} (describe your package)"

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %{"#{f}" or "#{t}" is not a summary}, e.message
    end
  end

  def test_version
    assert_equal Gem::Version.new('1'), @a1.version
  end

  def test_version_change_reset_full_name
    orig_full_name = @a1.full_name

    @a1.version = "2"

    refute_equal orig_full_name, @a1.full_name
  end

  def test_version_change_reset_cache_file
    orig_cache_file = @a1.cache_file

    @a1.version = "2"

    refute_equal orig_cache_file, @a1.cache_file
  end

  def test__load_fixes_Date_objects
    spec = new_spec "a", 1
    spec.instance_variable_set :@date, Date.today

    spec = Marshal.load Marshal.dump(spec)

    assert_kind_of Time, spec.date
  end

  def test_load_errors_contain_filename
    specfile = Tempfile.new(self.class.name.downcase)
    specfile.write "raise 'boom'"
    specfile.close
    begin
      capture_io do
        Gem::Specification.load(specfile.path)
      end
    rescue => e
      name_rexp = Regexp.new(Regexp.escape(specfile.path))
      assert e.backtrace.grep(name_rexp).any?
    end
  ensure
    specfile.delete
  end

  ##
  # KEEP p-1-x86-darwin-8
  # KEEP p-1
  # KEEP c-1.2
  # KEEP a_evil-9
  #      a-1
  #      a-1-x86-my_platform-1
  # KEEP a-2
  #      a-2-x86-other_platform-1
  # KEEP a-2-x86-my_platform-1
  #      a-3.a
  # KEEP a-3-x86-other_platform-1

  def test_latest_specs
    util_clear_gems
    util_setup_fake_fetcher

    quick_spec 'p', '1'

    p1_curr = quick_spec 'p', '1' do |spec|
      spec.platform = Gem::Platform::CURRENT
    end

    quick_spec @a1.name, @a1.version do |s|
      s.platform = Gem::Platform.new 'x86-my_platform1'
    end

    quick_spec @a1.name, @a1.version do |s|
      s.platform = Gem::Platform.new 'x86-third_platform1'
    end

    quick_spec @a2.name, @a2.version do |s|
      s.platform = Gem::Platform.new 'x86-my_platform1'
    end

    quick_spec @a2.name, @a2.version do |s|
      s.platform = Gem::Platform.new 'x86-other_platform1'
    end

    quick_spec @a2.name, @a2.version.bump do |s|
      s.platform = Gem::Platform.new 'x86-other_platform1'
    end

    Gem::Specification.remove_spec @b2
    Gem::Specification.remove_spec @pl1

    expected = %W[
                  a-2
                  a-2-x86-my_platform-1
                  a-3-x86-other_platform-1
                  a_evil-9
                  c-1.2
                  dep_x-1
                  p-1
                  #{p1_curr.full_name}
                  x-1
                 ]

    latest_specs = Gem::Specification.latest_specs.map(&:full_name).sort

    assert_equal expected, latest_specs
  end

  def test_metadata_validates_ok
    util_setup_validate

    Dir.chdir @tempdir do
      @m1 = quick_gem 'm', '1' do |s|
        s.files = %w[lib/code.rb]
        s.metadata = { 'one' => "two", 'two' => "three" }
      end

      use_ui @ui do
        @m1.validate
      end
    end
  end

  def test_metadata_key_type_validation_fails
    util_setup_validate

    Dir.chdir @tempdir do
      @m2 = quick_gem 'm', '2' do |s|
        s.files = %w[lib/code.rb]
        s.metadata = { 1 => "fail" }
      end

      e = assert_raises Gem::InvalidSpecificationException do
        @m2.validate
      end

      assert_equal "metadata keys must be a String", e.message
    end
  end

  def test_metadata_key_size_validation_fails
    util_setup_validate

    Dir.chdir @tempdir do
      @m2 = quick_gem 'm', '2' do |s|
        s.files = %w[lib/code.rb]
        s.metadata = { ("x" * 129) => "fail" }
      end

      e = assert_raises Gem::InvalidSpecificationException do
        @m2.validate
      end

      assert_equal "metadata key too large (129 > 128)", e.message
    end
  end

  def test_metadata_value_type_validation_fails
    util_setup_validate

    Dir.chdir @tempdir do
      @m2 = quick_gem 'm', '2' do |s|
        s.files = %w[lib/code.rb]
        s.metadata = { 'fail' => [] }
      end

      e = assert_raises Gem::InvalidSpecificationException do
        @m2.validate
      end

      assert_equal "metadata values must be a String", e.message
    end
  end

  def test_metadata_value_size_validation_fails
    util_setup_validate

    Dir.chdir @tempdir do
      @m2 = quick_gem 'm', '2' do |s|
        s.files = %w[lib/code.rb]
        s.metadata = { 'fail' => ("x" * 1025) }
      end

      e = assert_raises Gem::InvalidSpecificationException do
        @m2.validate
      end

      assert_equal "metadata value too large (1025 > 1024)", e.message
    end
  end

  def test_metadata_specs
    valid_ruby_spec = <<-EOF
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "m"
  s.version = "1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.metadata = { "one" => "two", "two" => "three" } if s.respond_to? :metadata=
  s.authors = ["A User"]
  s.date = "#{Gem::Specification::TODAY.strftime("%Y-%m-%d")}"
  s.description = "This is a test description"
  s.email = "example@example.com"
  s.files = ["lib/code.rb"]
  s.homepage = "http://example.com"
  s.require_paths = ["lib"]
  s.rubygems_version = "#{Gem::VERSION}"
  s.summary = "this is a summary"
end
    EOF

    @m1 = quick_gem 'm', '1' do |s|
      s.files = %w[lib/code.rb]
      s.metadata = { 'one' => "two", 'two' => "three" }
    end

    assert_equal @m1.to_ruby, valid_ruby_spec
  end

  def test_find_by_name
    util_make_gems
    assert(Gem::Specification.find_by_name("a"))
    assert(Gem::Specification.find_by_name("a", "1"))
    assert(Gem::Specification.find_by_name("a", ">1"))
    assert_raises(Gem::LoadError) do
      Gem::Specification.find_by_name("monkeys")
    end
  end

  def test_find_by_path
    a = new_spec "foo", "1", nil, "lib/foo.rb"

    install_specs a

    assert_equal a, Gem::Specification.find_by_path('foo')
    a.activate
    assert_equal a, Gem::Specification.find_by_path('foo')
  end

  def test_find_inactive_by_path
    a = new_spec "foo", "1", nil, "lib/foo.rb"

    install_specs a

    assert_equal a, Gem::Specification.find_inactive_by_path('foo')
    a.activate
    assert_equal nil, Gem::Specification.find_inactive_by_path('foo')
  end

  def test_load_default_gem
    Gem::Specification.reset
    assert_equal [], Gem::Specification.map(&:full_name)

    default_gem_spec = new_default_spec("default", "2.0.0.0",
                                        nil, "default/gem.rb")
    spec_path = File.join(@default_spec_dir, default_gem_spec.spec_name)
    write_file(spec_path) do |file|
      file.print(default_gem_spec.to_ruby)
    end
    Gem::Specification.reset
    assert_equal ["default-2.0.0.0"], Gem::Specification.map(&:full_name)
  end

  def util_setup_deps
    @gem = quick_spec "awesome", "1.0" do |awesome|
      awesome.add_runtime_dependency "bonobo", []
      awesome.add_development_dependency "monkey", []
    end

    @bonobo = Gem::Dependency.new("bonobo", [])
    @monkey = Gem::Dependency.new("monkey", [], :development)
  end

  def util_setup_validate
    Dir.chdir @tempdir do
      FileUtils.mkdir_p File.join("ext", "a")
      FileUtils.mkdir_p "lib"
      FileUtils.mkdir_p "test"
      FileUtils.mkdir_p "bin"

      FileUtils.touch File.join("ext", "a", "extconf.rb")
      FileUtils.touch File.join("lib", "code.rb")
      FileUtils.touch File.join("test", "suite.rb")

      File.open "bin/exec", "w", 0755 do |fp|
        fp.puts "#!#{Gem.ruby}"
      end
    end
  end

  def with_syck
    begin
      require "yaml"
      old_engine = YAML::ENGINE.yamler
      verbose, $VERBOSE = $VERBOSE, nil
      YAML::ENGINE.yamler = 'syck'
      load 'rubygems/syck_hack.rb'
    rescue NameError
      # probably on 1.8, ignore
    ensure
      $VERBOSE = verbose
    end

    yield
  ensure
    begin
      YAML::ENGINE.yamler = old_engine
      load 'rubygems/syck_hack.rb'
    rescue NameError
      # ignore
    end
  end

  def with_psych
    begin
      require "yaml"
      old_engine = YAML::ENGINE.yamler
      YAML::ENGINE.yamler = 'psych'
      load 'rubygems/syck_hack.rb'
    rescue NameError
      # probably on 1.8, ignore
    end

    yield
  ensure
    begin
      YAML::ENGINE.yamler = old_engine
      load 'rubygems/syck_hack.rb'
    rescue NameError
      # ignore
    end
  end

  def silence_warnings
    old_verbose, $VERBOSE = $VERBOSE, false
    yield
  ensure
    $VERBOSE = old_verbose
  end
end
