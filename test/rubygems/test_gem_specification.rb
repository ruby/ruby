#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'stringio'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/specification'

class TestGemSpecification < RubyGemTestCase

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
  s.files = ["lib/keyedlist.rb"]
  s.require_paths = ["lib"]
  s.autorequire = %q{keyedlist}
  s.author = %q{Florian Gross}
  s.email = %q{flgr@ccan.de}
end
  EOF

  def setup
    super

    @a1 = quick_gem 'a', '1' do |s|
      s.executable = 'exec'
      s.extensions << 'ext/a/extconf.rb'
      s.has_rdoc = 'true'
      s.test_file = 'test/suite.rb'
      s.requirements << 'A working computer'
      s.rubyforge_project = 'example'

      s.add_dependency 'rake', '> 0.4'
      s.add_dependency 'jabber4r', '> 0.0.0'
      s.add_dependency 'pqa', ['> 0.4', '<= 0.6']

      s.mark_version
      s.files = %w[lib/code.rb]
    end

    @a2 = quick_gem 'a', '2' do |s|
      s.files = %w[lib/code.rb]
    end

    FileUtils.mkdir_p File.join(@tempdir, 'bin')
    File.open File.join(@tempdir, 'bin', 'exec'), 'w' do |fp|
      fp.puts "#!#{Gem.ruby}"
    end

    @current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
  end

  def test_self_attribute_names
    expected_value = %w[
      authors
      autorequire
      bindir
      cert_chain
      date
      default_executable
      dependencies
      description
      email
      executables
      extensions
      extra_rdoc_files
      files
      has_rdoc
      homepage
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

  def test_self_load
    spec = File.join @gemhome, 'specifications', "#{@a2.full_name}.gemspec"
    gs = Gem::Specification.load spec

    assert_equal @a2, gs
  end

  def test_self_load_legacy_ruby
    spec = eval LEGACY_RUBY_SPEC
    assert_equal 'keyedlist', spec.name
    assert_equal '0.4.0', spec.version.to_s
    assert_equal true, spec.has_rdoc?
    assert_equal Gem::Specification::TODAY, spec.date
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new('1'))
    assert_equal false, spec.has_unit_tests?
  end

  def test_self_load_legacy_yaml
    s = YAML.load StringIO.new(LEGACY_YAML_SPEC)
    assert_equal 'keyedlist', s.name
    assert_equal '0.4.0', s.version.to_s
    assert_equal true, s.has_rdoc?
    #assert_equal Date.today, s.date
    #assert s.required_ruby_version.satisfied_by?(Gem::Version.new('1'))
    assert_equal false, s.has_unit_tests?
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
    assert_equal false, spec.has_rdoc
    assert_equal false, spec.has_rdoc?
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

  def test__dump
    @a2.platform = Gem::Platform.local
    @a2.instance_variable_set :@original_platform, 'old_platform'

    data = Marshal.dump @a2

    same_spec = Marshal.load data

    assert_equal 'old_platform', same_spec.original_platform
  end

  def test_add_dependency_with_explicit_type
    gem = quick_gem "awesome", "1.0" do |awesome|
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
    assert_equal Time.local(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_string
    @a1.date = '2003-09-17'
    assert_equal Time.local(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_time
    @a1.date = Time.local(2003, 9, 17, 0,0,0)
    assert_equal Time.local(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_time_local
    # HACK PDT
    @a1.date = Time.local(2003, 9, 17, 19,50,0)
    assert_equal Time.local(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_time_utc
    # HACK PDT
    @a1.date = Time.local(2003, 9, 17, 19,50,0)
    assert_equal Time.local(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_default_executable
    assert_equal 'exec', @a1.default_executable

    @a1.default_executable = nil
    @a1.instance_variable_set :@executables, nil
    assert_equal nil, @a1.default_executable
  end

  def test_dependencies
    rake = Gem::Dependency.new 'rake', '> 0.4'
    jabber = Gem::Dependency.new 'jabber4r', '> 0.0.0'
    pqa = Gem::Dependency.new 'pqa', ['> 0.4', '<= 0.6']

    assert_equal [rake, jabber, pqa], @a1.dependencies
  end

  def test_dependencies_scoped_by_type
    gem = quick_gem "awesome", "1.0" do |awesome|
      awesome.add_runtime_dependency "bonobo", []
      awesome.add_development_dependency "monkey", []
    end

    bonobo = Gem::Dependency.new("bonobo", [])
    monkey = Gem::Dependency.new("monkey", [], :development)

    assert_equal([bonobo, monkey], gem.dependencies)
    assert_equal([bonobo], gem.runtime_dependencies)
    assert_equal([monkey], gem.development_dependencies)
  end

  def test_description
    assert_equal 'This is a test description', @a1.description
  end

  def test_eql_eh
    g1 = quick_gem 'gem'
    g2 = quick_gem 'gem'

    assert_equal g1, g2
    assert_equal g1.hash, g2.hash
    assert_equal true, g1.eql?(g2)
  end

  def test_equals2
    assert_equal @a1, @a1
    assert_equal @a1, @a1.dup
    refute_equal @a1, @a2
    refute_equal @a1, Object.new
  end

  # The cgikit specification was reported to be causing trouble in at least
  # one version of RubyGems, so we test explicitly for it.
  def test_equals2_cgikit
    cgikit = Gem::Specification.new do |s|
      s.name = %q{cgikit}
      s.version = "1.1.0"
      s.date = %q{2004-03-13}
      s.summary = %q{CGIKit is a componented-oriented web application } +
      %q{framework like Apple Computers WebObjects.  } +
      %{This framework services Model-View-Controller architecture } +
      %q{programming by components based on a HTML file, a definition } +
      %q{file and a Ruby source.  }
      s.email = %q{info@spice-of-life.net}
      s.homepage = %q{http://www.spice-of-life.net/download/cgikit/}
      s.autorequire = %q{cgikit}
      s.bindir = nil
      s.has_rdoc = nil
      s.required_ruby_version = nil
      s.platform = nil
      s.files = ["lib/cgikit", "lib/cgikit.rb", "lib/cgikit/components", "..."]
    end

    assert_equal cgikit, cgikit
  end

  def test_equals2_default_executable
    spec = @a1.dup
    spec.default_executable = 'xx'

    refute_equal @a1, spec
    refute_equal spec, @a1
  end

  def test_equals2_extensions
    spec = @a1.dup
    spec.extensions = 'xx'

    refute_equal @a1, spec
    refute_equal spec, @a1
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

  def test_full_gem_path
    assert_equal File.join(@gemhome, 'gems', @a1.full_name),
                 @a1.full_gem_path

    @a1.original_platform = 'mswin32'

    assert_equal File.join(@gemhome, 'gems', @a1.original_name),
                 @a1.full_gem_path
  end

  def test_full_gem_path_double_slash
    gemhome = @gemhome.sub(/\w\//, '\&/')
    @a1.loaded_from = File.join gemhome, 'specifications',
                                "#{@a1.full_name}.gemspec"

    assert_equal File.join(@gemhome, 'gems', @a1.full_name),
                 @a1.full_gem_path
  end

  def test_full_name
    assert_equal 'a-1', @a1.full_name

    @a1.platform = Gem::Platform.new ['universal', 'darwin', nil]
    assert_equal 'a-1-universal-darwin', @a1.full_name

    @a1.instance_variable_set :@new_platform, 'mswin32'
    assert_equal 'a-1-mswin32', @a1.full_name, 'legacy'

    return if win_platform?

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
      util_set_arch arch
      @a1.platform = 'current'
      assert_equal expected, @a1.full_name
    end
  end

  def test_has_rdoc_eh
    assert @a1.has_rdoc?
  end

  def test_hash
    assert_equal @a1.hash, @a1.hash
    assert_equal @a1.hash, @a1.dup.hash
    refute_equal @a1.hash, @a2.hash
  end

  def test_lib_files
    @a1.files = %w[lib/foo.rb Rakefile]

    assert_equal %w[lib/foo.rb], @a1.lib_files
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
    s1 = quick_gem 'a', '1'
    s2 = quick_gem 'b', '1'

    assert_equal(-1, (s1 <=> s2))
    assert_equal( 0, (s1 <=> s1))
    assert_equal( 1, (s2 <=> s1))
  end

  def test_spaceship_platform
    s1 = quick_gem 'a', '1'
    s2 = quick_gem 'a', '1' do |s|
      s.platform = Gem::Platform.new 'x86-my_platform1'
    end

    assert_equal( -1, (s1 <=> s2))
    assert_equal(  0, (s1 <=> s1))
    assert_equal(  1, (s2 <=> s1))
  end

  def test_spaceship_version
    s1 = quick_gem 'a', '1'
    s2 = quick_gem 'a', '2'

    assert_equal( -1, (s1 <=> s2))
    assert_equal(  0, (s1 <=> s1))
    assert_equal(  1, (s2 <=> s1))
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
  s.name = %q{a}
  s.version = \"2\"

  s.required_rubygems_version = Gem::Requirement.new(\"> 0\") if s.respond_to? :required_rubygems_version=
  s.authors = [\"A User\"]
  s.date = %q{#{Gem::Specification::TODAY.strftime "%Y-%m-%d"}}
  s.description = %q{This is a test description}
  s.email = %q{example@example.com}
  s.files = [\"lib/code.rb\"]
  s.has_rdoc = true
  s.homepage = %q{http://example.com}
  s.require_paths = [\"lib\"]
  s.rubygems_version = %q{#{Gem::RubyGemsVersion}}
  s.summary = %q{this is a summary}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = #{Gem::Specification::CURRENT_SPECIFICATION_VERSION}

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
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

  def test_to_ruby_fancy
    @a1.platform = Gem::Platform.local
    ruby_code = @a1.to_ruby

    local = Gem::Platform.local
    expected_platform = "[#{local.cpu.inspect}, #{local.os.inspect}, #{local.version.inspect}]"

    expected = <<-SPEC
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{a}
  s.version = \"1\"
  s.platform = Gem::Platform.new(#{expected_platform})

  s.required_rubygems_version = Gem::Requirement.new(\">= 0\") if s.respond_to? :required_rubygems_version=
  s.authors = [\"A User\"]
  s.date = %q{#{Gem::Specification::TODAY.strftime "%Y-%m-%d"}}
  s.default_executable = %q{exec}
  s.description = %q{This is a test description}
  s.email = %q{example@example.com}
  s.executables = [\"exec\"]
  s.extensions = [\"ext/a/extconf.rb\"]
  s.files = [\"lib/code.rb\", \"test/suite.rb\", \"bin/exec\", \"ext/a/extconf.rb\"]
  s.has_rdoc = %q{true}
  s.homepage = %q{http://example.com}
  s.require_paths = [\"lib\"]
  s.requirements = [\"A working computer\"]
  s.rubyforge_project = %q{example}
  s.rubygems_version = %q{#{Gem::RubyGemsVersion}}
  s.summary = %q{this is a summary}
  s.test_files = [\"test/suite.rb\"]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<rake>, [\"> 0.4\"])
      s.add_runtime_dependency(%q<jabber4r>, [\"> 0.0.0\"])
      s.add_runtime_dependency(%q<pqa>, [\"> 0.4\", \"<= 0.6\"])
    else
      s.add_dependency(%q<rake>, [\"> 0.4\"])
      s.add_dependency(%q<jabber4r>, [\"> 0.0.0\"])
      s.add_dependency(%q<pqa>, [\"> 0.4\", \"<= 0.6\"])
    end
  else
    s.add_dependency(%q<rake>, [\"> 0.4\"])
    s.add_dependency(%q<jabber4r>, [\"> 0.0.0\"])
    s.add_dependency(%q<pqa>, [\"> 0.4\", \"<= 0.6\"])
  end
end
    SPEC

    assert_equal expected, ruby_code

    same_spec = eval ruby_code

    assert_equal @a1, same_spec
  end

  def test_to_ruby_legacy
    gemspec1 = eval LEGACY_RUBY_SPEC
    ruby_code = gemspec1.to_ruby
    gemspec2 = eval ruby_code

    assert_equal gemspec1, gemspec2
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
    same_spec = YAML.load(yaml_str)

    assert_equal @a1, same_spec
  end

  def test_to_yaml_fancy
    @a1.platform = Gem::Platform.local
    yaml_str = @a1.to_yaml

    same_spec = YAML.load(yaml_str)

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

    same_spec = YAML.load(yaml_str)

    assert_equal Gem::Platform.new('powerpc-darwin7'), same_spec.platform
    assert_equal 'powerpc-darwin7.9.0', same_spec.original_platform
  end

  def test_to_yaml_platform_nil
    @a1.instance_variable_set :@original_platform, nil

    assert_match %r|^platform: ruby$|, @a1.to_yaml
  end

  def test_validate
    Dir.chdir @tempdir do
      assert @a1.validate
    end
  end

  def test_validate_authors
    Dir.chdir @tempdir do
      @a1.authors = []

      use_ui @ui do
        @a1.validate
      end

      assert_equal "WARNING:  no author specified\n", @ui.error, 'error'

      @a1.authors = [Object.new]

      e = assert_raises Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal 'authors must be Array of Strings', e.message
    end
  end

  def test_validate_autorequire
    Dir.chdir @tempdir do
      @a1.autorequire = 'code'

      use_ui @ui do
        @a1.validate
      end

      assert_equal "WARNING:  deprecated autorequire specified\n",
                   @ui.error, 'error'
    end
  end

  def test_validate_email
    Dir.chdir @tempdir do
      @a1.email = ''

      use_ui @ui do
        @a1.validate
      end

      assert_equal "WARNING:  no email specified\n", @ui.error, 'error'
    end
  end

  def test_validate_empty
    e = assert_raises Gem::InvalidSpecificationException do
      Gem::Specification.new.validate
    end

    assert_equal 'missing value for attribute name', e.message
  end

  def test_validate_executables
    FileUtils.mkdir_p File.join(@tempdir, 'bin')
    File.open File.join(@tempdir, 'bin', 'exec'), 'w' do end

    use_ui @ui do
      Dir.chdir @tempdir do
        assert @a1.validate
      end
    end

    assert_equal '', @ui.output, 'output'
    assert_equal "WARNING:  bin/exec is missing #! line\n", @ui.error, 'error'
  end

  def test_validate_empty_require_paths
    @a1.require_paths = []
    e = assert_raises Gem::InvalidSpecificationException do
      @a1.validate
    end

    assert_equal 'specification must have at least one require_path', e.message
  end

  def test_validate_homepage
    Dir.chdir @tempdir do
      @a1.homepage = ''

      use_ui @ui do
        @a1.validate
      end

      assert_equal "WARNING:  no homepage specified\n", @ui.error, 'error'
    end
  end

  def test_validate_has_rdoc
    Dir.chdir @tempdir do
      @a1.has_rdoc = false

      use_ui @ui do
        @a1.validate
      end

      assert_equal "WARNING:  RDoc will not be generated (has_rdoc == false)\n",
                   @ui.error, 'error'
    end
  end

  def test_validate_platform_legacy
    Dir.chdir @tempdir do
      @a1.platform = 'mswin32'
      assert @a1.validate

      @a1.platform = 'i586-linux'
      assert @a1.validate

      @a1.platform = 'powerpc-darwin'
      assert @a1.validate
    end
  end

  def test_validate_rubyforge_project
    Dir.chdir @tempdir do
      @a1.rubyforge_project = ''

      use_ui @ui do
        @a1.validate
      end

      assert_equal "WARNING:  no rubyforge_project specified\n",
                   @ui.error, 'error'
    end
  end

  def test_validate_rubygems_version
    @a1.rubygems_version = "3"
    e = assert_raises Gem::InvalidSpecificationException do
      @a1.validate
    end

    assert_equal "expected RubyGems version #{Gem::RubyGemsVersion}, was 3",
                 e.message
  end

  def test_validate_summary
    Dir.chdir @tempdir do
      @a1.summary = ''

      use_ui @ui do
        @a1.validate
      end

      assert_equal "WARNING:  no summary specified\n", @ui.error, 'error'
    end
  end

  def test_version
    assert_equal Gem::Version.new('1'), @a1.version
  end

end

