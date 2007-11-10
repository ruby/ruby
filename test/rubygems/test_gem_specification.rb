#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'stringio'
require 'test/unit'
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

    @a0_0_1 = quick_gem 'a', '0.0.1' do |s|
      s.executable = 'exec'
      s.extensions << 'ext/a/extconf.rb'
      s.has_rdoc = 'true'
      s.test_file = 'test/suite.rb'
      s.requirements << 'A working computer'

      s.add_dependency 'rake', '> 0.4'
      s.add_dependency 'jabber4r', '> 0.0.0'
      s.add_dependency 'pqa', ['> 0.4', '<= 0.6']

      s.mark_version
      s.files = %w[lib/code.rb]
    end

    @a0_0_2 = quick_gem 'a', '0.0.2' do |s|
      s.files = %w[lib/code.rb]
    end
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

  def test_self_load
    spec = File.join @gemhome, 'specifications', "#{@a0_0_2.full_name}.gemspec"
    gs = Gem::Specification.load spec

    assert_equal @a0_0_2, gs
  end

  def test_self_load_legacy_ruby
    s = eval LEGACY_RUBY_SPEC
    assert_equal 'keyedlist', s.name
    assert_equal '0.4.0', s.version.to_s
    assert_equal true, s.has_rdoc?
    assert_equal Gem::Specification::TODAY, s.date
    assert s.required_ruby_version.satisfied_by?(Gem::Version.new('0.0.1'))
    assert_equal false, s.has_unit_tests?
  end

  def test_self_load_legacy_yaml
    s = YAML.load StringIO.new(LEGACY_YAML_SPEC)
    assert_equal 'keyedlist', s.name
    assert_equal '0.4.0', s.version.to_s
    assert_equal true, s.has_rdoc?
    #assert_equal Date.today, s.date
    #assert s.required_ruby_version.satisfied_by?(Gem::Version.new('0.0.1'))
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

  def test_author
    assert_equal 'A User', @a0_0_1.author
  end

  def test_authors
    assert_equal ['A User'], @a0_0_1.authors
  end

  def test_bindir_equals
    @a0_0_1.bindir = 'apps'

    assert_equal 'apps', @a0_0_1.bindir
  end

  def test_bindir_equals_nil
    @a0_0_2.bindir = nil
    @a0_0_2.executable = 'app'

    assert_equal nil, @a0_0_2.bindir
    assert_equal %w[lib/code.rb app], @a0_0_2.files
  end

  def test_date
    assert_equal Gem::Specification::TODAY, @a0_0_1.date
  end

  def test_date_equals_date
    @a0_0_1.date = Date.new(2003, 9, 17)
    assert_equal Time.local(2003, 9, 17, 0,0,0), @a0_0_1.date
  end

  def test_date_equals_string
    @a0_0_1.date = '2003-09-17'
    assert_equal Time.local(2003, 9, 17, 0,0,0), @a0_0_1.date
  end

  def test_date_equals_time
    @a0_0_1.date = Time.local(2003, 9, 17, 0,0,0)
    assert_equal Time.local(2003, 9, 17, 0,0,0), @a0_0_1.date
  end

  def test_date_equals_time_local
    # HACK PDT
    @a0_0_1.date = Time.local(2003, 9, 17, 19,50,0)
    assert_equal Time.local(2003, 9, 17, 0,0,0), @a0_0_1.date
  end

  def test_date_equals_time_utc
    # HACK PDT
    @a0_0_1.date = Time.local(2003, 9, 17, 19,50,0)
    assert_equal Time.local(2003, 9, 17, 0,0,0), @a0_0_1.date
  end

  def test_default_executable
    assert_equal 'exec', @a0_0_1.default_executable

    @a0_0_1.default_executable = nil
    @a0_0_1.instance_variable_set :@executables, nil
    assert_equal nil, @a0_0_1.default_executable
  end

  def test_dependencies
    rake = Gem::Dependency.new 'rake', '> 0.4'
    jabber = Gem::Dependency.new 'jabber4r', '> 0.0.0'
    pqa = Gem::Dependency.new 'pqa', ['> 0.4', '<= 0.6']

    assert_equal [rake, jabber, pqa], @a0_0_1.dependencies
  end

  def test_description
    assert_equal 'This is a test description', @a0_0_1.description
  end

  def test_eql_eh
    g1 = quick_gem 'gem'
    g2 = quick_gem 'gem'

    assert_equal g1, g2
    assert_equal g1.hash, g2.hash
    assert_equal true, g1.eql?(g2)
  end

  def test_equals2
    assert_equal @a0_0_1, @a0_0_1
    assert_equal @a0_0_1, @a0_0_1.dup
    assert_not_equal @a0_0_1, @a0_0_2
    assert_not_equal @a0_0_1, Object.new
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
    spec = @a0_0_1.dup
    spec.default_executable = 'xx'

    assert_not_equal @a0_0_1, spec
    assert_not_equal spec, @a0_0_1
  end

  def test_equals2_extensions
    spec = @a0_0_1.dup
    spec.extensions = 'xx'

    assert_not_equal @a0_0_1, spec
    assert_not_equal spec, @a0_0_1
  end

  def test_executables
    @a0_0_1.executable = 'app'
    assert_equal %w[app], @a0_0_1.executables
  end

  def test_executable_equals
    @a0_0_2.executable = 'app'
    assert_equal 'app', @a0_0_2.executable
    assert_equal %w[lib/code.rb bin/app], @a0_0_2.files
  end

  def test_extensions
    assert_equal ['ext/a/extconf.rb'], @a0_0_1.extensions
  end

  def test_files
    @a0_0_1.files = %w(files bin/common)
    @a0_0_1.test_files = %w(test_files bin/common)
    @a0_0_1.executables = %w(executables common)
    @a0_0_1.extra_rdoc_files = %w(extra_rdoc_files bin/common)
    @a0_0_1.extensions = %w(extensions bin/common)

    expected = %w[
      bin/common
      bin/executables
      extensions
      extra_rdoc_files
      files
      test_files
    ]
    assert_equal expected, @a0_0_1.files.sort
  end

  def test_files_duplicate
    @a0_0_2.files = %w[a b c d b]
    @a0_0_2.extra_rdoc_files = %w[x y z x]
    @a0_0_2.normalize

    assert_equal %w[a b c d x y z], @a0_0_2.files
    assert_equal %w[x y z], @a0_0_2.extra_rdoc_files
  end

  def test_files_extra_rdoc_files
    @a0_0_2.files = %w[a b c d]
    @a0_0_2.extra_rdoc_files = %w[x y z]
    @a0_0_2.normalize
    assert_equal %w[a b c d x y z], @a0_0_2.files
  end

  def test_files_non_array
    @a0_0_1.files = "F"
    @a0_0_1.test_files = "TF"
    @a0_0_1.executables = "X"
    @a0_0_1.extra_rdoc_files = "ERF"
    @a0_0_1.extensions = "E"

    assert_equal %w[E ERF F TF bin/X], @a0_0_1.files.sort
  end

  def test_files_non_array_pathological
    @a0_0_1.instance_variable_set :@files, "F"
    @a0_0_1.instance_variable_set :@test_files, "TF"
    @a0_0_1.instance_variable_set :@extra_rdoc_files, "ERF"
    @a0_0_1.instance_variable_set :@extensions, "E"
    @a0_0_1.instance_variable_set :@executables, "X"

    assert_equal %w[E ERF F TF bin/X], @a0_0_1.files.sort
    assert_kind_of Integer, @a0_0_1.hash
  end

  def test_full_name
    assert_equal 'a-0.0.1', @a0_0_1.full_name

    @a0_0_1.platform = Gem::Platform.new ['universal', 'darwin', nil]
    assert_equal 'a-0.0.1-universal-darwin', @a0_0_1.full_name

    @a0_0_1.instance_variable_set :@new_platform, 'mswin32'
    assert_equal 'a-0.0.1-mswin32', @a0_0_1.full_name, 'legacy'

    return if win_platform?

    @a0_0_1.platform = 'current'
    assert_equal 'a-0.0.1-x86-darwin-8', @a0_0_1.full_name
  end

  def test_full_name_windows
    test_cases = {
      'i386-mswin32'      => 'a-0.0.1-x86-mswin32-60',
      'i386-mswin32_80'   => 'a-0.0.1-x86-mswin32-80',
      'i386-mingw32'      => 'a-0.0.1-x86-mingw32'
    }
    
    test_cases.each do |arch, expected|
      util_set_arch arch
      @a0_0_1.platform = 'current'
      assert_equal expected, @a0_0_1.full_name
    end
  end

  def test_has_rdoc_eh
    assert_equal true, @a0_0_1.has_rdoc?
  end

  def test_hash
    assert_equal @a0_0_1.hash, @a0_0_1.hash
    assert_equal @a0_0_1.hash, @a0_0_1.dup.hash
    assert_not_equal @a0_0_1.hash, @a0_0_2.hash
  end

  def test_lib_files
    @a0_0_1.files = %w[lib/foo.rb Rakefile]

    assert_equal %w[lib/foo.rb], @a0_0_1.lib_files
  end

  def test_name
    assert_equal 'a', @a0_0_1.name
  end

  def test_platform
    assert_equal Gem::Platform::RUBY, @a0_0_1.platform
  end

  def test_platform_equals
    @a0_0_1.platform = nil
    assert_equal Gem::Platform::RUBY, @a0_0_1.platform

    @a0_0_1.platform = Gem::Platform::RUBY
    assert_equal Gem::Platform::RUBY, @a0_0_1.platform

    test_cases = {
      'i386-mswin32'    => ['x86', 'mswin32', '60'],
      'i386-mswin32_80' => ['x86', 'mswin32', '80'],
      'i386-mingw32'    => ['x86', 'mingw32', nil ],
      'x86-darwin8'     => ['x86', 'darwin',  '8' ],
    }

    test_cases.each do |arch, expected|
      util_set_arch arch
      @a0_0_1.platform = Gem::Platform::CURRENT
      assert_equal Gem::Platform.new(expected), @a0_0_1.platform
    end
  end

  def test_platform_equals_legacy
    @a0_0_1.platform = Gem::Platform::WIN32
    assert_equal Gem::Platform::MSWIN32, @a0_0_1.platform

    @a0_0_1.platform = Gem::Platform::LINUX_586
    assert_equal Gem::Platform::X86_LINUX, @a0_0_1.platform

    @a0_0_1.platform = Gem::Platform::DARWIN
    assert_equal Gem::Platform::PPC_DARWIN, @a0_0_1.platform
  end

  def test_require_paths
    @a0_0_1.require_path = 'lib'
    assert_equal %w[lib], @a0_0_1.require_paths
  end

  def test_requirements
    assert_equal ['A working computer'], @a0_0_1.requirements
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
    assert_equal 'this is a summary', @a0_0_1.summary
  end

  def test_test_files
    @a0_0_1.test_file = 'test/suite.rb'
    assert_equal ['test/suite.rb'], @a0_0_1.test_files
  end

  def test_test_suite_file
    @a0_0_2.test_suite_file = 'test/suite.rb'
    assert_equal ['test/suite.rb'], @a0_0_2.test_files
    # XXX: what about the warning?
  end

  def test_to_ruby
    @a0_0_2.required_rubygems_version = Gem::Requirement.new '> 0'

    ruby_code = @a0_0_2.to_ruby

    expected = "Gem::Specification.new do |s|
  s.name = %q{a}
  s.version = \"0.0.2\"

  s.specification_version = #{Gem::Specification::CURRENT_SPECIFICATION_VERSION} if s.respond_to? :specification_version=

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
end
"

    assert_equal expected, ruby_code

    same_spec = eval ruby_code

    assert_equal @a0_0_2, same_spec
  end

  def test_to_ruby_fancy
    @a0_0_1.platform = Gem::Platform::PPC_DARWIN
    ruby_code = @a0_0_1.to_ruby

    expected = "Gem::Specification.new do |s|
  s.name = %q{a}
  s.version = \"0.0.1\"

  s.specification_version = 2 if s.respond_to? :specification_version=

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
  s.platform = Gem::Platform.new([\"ppc\", \"darwin\", nil])
  s.require_paths = [\"lib\"]
  s.requirements = [\"A working computer\"]
  s.rubygems_version = %q{0.9.4.6}
  s.summary = %q{this is a summary}
  s.test_files = [\"test/suite.rb\"]

  s.add_dependency(%q<rake>, [\"> 0.4\"])
  s.add_dependency(%q<jabber4r>, [\"> 0.0.0\"])
  s.add_dependency(%q<pqa>, [\"> 0.4\", \"<= 0.6\"])
end
"

    assert_equal expected, ruby_code

    same_spec = eval ruby_code

    assert_equal @a0_0_1, same_spec
  end

  def test_to_ruby_legacy
    gemspec1 = eval LEGACY_RUBY_SPEC
    ruby_code = gemspec1.to_ruby
    gemspec2 = eval ruby_code

    assert_equal gemspec1, gemspec2
  end

  def test_to_yaml
    yaml_str = @a0_0_1.to_yaml
    same_spec = YAML.load(yaml_str)

    assert_equal @a0_0_1, same_spec
  end

  def test_to_yaml_fancy
    @a0_0_1.platform = Gem::Platform::PPC_DARWIN
    yaml_str = @a0_0_1.to_yaml

    same_spec = YAML.load(yaml_str)

    assert_equal Gem::Platform::PPC_DARWIN, same_spec.platform

    assert_equal @a0_0_1, same_spec
  end

  def test_to_yaml_legacy_platform
    @a0_0_1.platform = 'powerpc-darwin7.9.0'

    yaml_str = @a0_0_1.to_yaml

    same_spec = YAML.load(yaml_str)

    assert_equal Gem::Platform.new('powerpc-darwin7'), same_spec.platform
    assert_equal 'powerpc-darwin7.9.0', same_spec.original_platform
  end

  def test_validate
    assert @a0_0_1.validate
  end

  def test_validate_empty
    e = assert_raise Gem::InvalidSpecificationException do
      Gem::Specification.new.validate
    end

    assert_equal 'missing value for attribute name', e.message
  end

  def test_validate_empty_require_paths
    @a0_0_1.require_paths = []
    e = assert_raise Gem::InvalidSpecificationException do
      @a0_0_1.validate
    end

    assert_equal 'specification must have at least one require_path', e.message
  end

  def test_validate_platform_bad
    @a0_0_1.platform = Object.new
    assert_raise Gem::InvalidSpecificationException do @a0_0_1.validate end

    @a0_0_1.platform = "my-custom-platform"
    e = assert_raise Gem::InvalidSpecificationException do
      @a0_0_1.validate
    end

    assert_equal 'invalid platform "my-custom-platform", see Gem::Platform',
                 e.message
  end

  def test_validate_platform_legacy
    @a0_0_1.platform = Gem::Platform::WIN32
    assert @a0_0_1.validate

    @a0_0_1.platform = Gem::Platform::LINUX_586
    assert @a0_0_1.validate

    @a0_0_1.platform = Gem::Platform::DARWIN
    assert @a0_0_1.validate
  end

  def test_validate_rubygems_version
    @a0_0_1.rubygems_version = "3"
    e = assert_raise Gem::InvalidSpecificationException do
      @a0_0_1.validate
    end

    assert_equal "expected RubyGems version #{Gem::RubyGemsVersion}, was 3",
                 e.message
  end

  def test_version
    assert_equal Gem::Version.new('0.0.1'), @a0_0_1.version
  end

end

