# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/platform'
require 'rbconfig'

class TestGemPlatform < Gem::TestCase
  def test_self_local
    util_set_arch 'i686-darwin8.10.1'

    assert_equal Gem::Platform.new(%w[x86 darwin 8]), Gem::Platform.local
  end

  def test_self_match
    Gem::Deprecate.skip_during do
      assert Gem::Platform.match(nil), 'nil == ruby'
      assert Gem::Platform.match(Gem::Platform.local), 'exact match'
      assert Gem::Platform.match(Gem::Platform.local.to_s), '=~ match'
      assert Gem::Platform.match(Gem::Platform::RUBY), 'ruby'
    end
  end

  def test_self_match_gem?
    assert Gem::Platform.match_gem?(nil, 'json'), 'nil == ruby'
    assert Gem::Platform.match_gem?(Gem::Platform.local, 'json'), 'exact match'
    assert Gem::Platform.match_gem?(Gem::Platform.local.to_s, 'json'), '=~ match'
    assert Gem::Platform.match_gem?(Gem::Platform::RUBY, 'json'), 'ruby'
  end

  def test_self_match_spec?
    make_spec = -> platform do
      util_spec 'mygem-for-platform-match_spec', '1' do |s|
        s.platform = platform
      end
    end

    assert Gem::Platform.match_spec?(make_spec.call(nil)), 'nil == ruby'
    assert Gem::Platform.match_spec?(make_spec.call(Gem::Platform.local)), 'exact match'
    assert Gem::Platform.match_spec?(make_spec.call(Gem::Platform.local.to_s)), '=~ match'
    assert Gem::Platform.match_spec?(make_spec.call(Gem::Platform::RUBY)), 'ruby'
  end

  def test_self_match_spec_with_match_gem_override
    make_spec = -> name, platform do
      util_spec name, '1' do |s|
        s.platform = platform
      end
    end

    class << Gem::Platform
      alias_method :original_match_gem?, :match_gem?
      def match_gem?(platform, gem_name)
        # e.g., sassc and libv8 are such gems, their native extensions do not use the Ruby C API
        if gem_name == 'gem-with-ruby-impl-independent-precompiled-ext'
          match_platforms?(platform, [Gem::Platform::RUBY, Gem::Platform.local])
        else
          match_platforms?(platform, Gem.platforms)
        end
      end
    end

    platforms = Gem.platforms
    Gem.platforms = [Gem::Platform::RUBY]
    begin
      assert_equal true,  Gem::Platform.match_spec?(make_spec.call('mygem', Gem::Platform::RUBY))
      assert_equal false, Gem::Platform.match_spec?(make_spec.call('mygem', Gem::Platform.local))

      name = 'gem-with-ruby-impl-independent-precompiled-ext'
      assert_equal true, Gem::Platform.match_spec?(make_spec.call(name, Gem::Platform.local))
    ensure
      Gem.platforms = platforms
      class << Gem::Platform
        remove_method :match_gem?
        alias_method :match_gem?, :original_match_gem? # rubocop:disable Lint/DuplicateMethods
        remove_method :original_match_gem?
      end
    end
  end

  def test_self_new
    assert_equal Gem::Platform.local, Gem::Platform.new(Gem::Platform::CURRENT)
    assert_equal Gem::Platform::RUBY, Gem::Platform.new(Gem::Platform::RUBY)
    assert_equal Gem::Platform::RUBY, Gem::Platform.new(nil)
    assert_equal Gem::Platform::RUBY, Gem::Platform.new('')
  end

  def test_initialize
    test_cases = {
      'amd64-freebsd6'         => ['amd64',     'freebsd',   '6'],
      'hppa2.0w-hpux11.31'     => ['hppa2.0w',  'hpux',      '11'],
      'java'                   => [nil,         'java',      nil],
      'jruby'                  => [nil,         'java',      nil],
      'universal-dotnet'       => ['universal', 'dotnet',    nil],
      'universal-dotnet2.0'    => ['universal', 'dotnet',  '2.0'],
      'universal-dotnet4.0'    => ['universal', 'dotnet',  '4.0'],
      'powerpc-aix5.3.0.0'     => ['powerpc',   'aix',       '5'],
      'powerpc-darwin7'        => ['powerpc',   'darwin',    '7'],
      'powerpc-darwin8'        => ['powerpc',   'darwin',    '8'],
      'powerpc-linux'          => ['powerpc',   'linux',     nil],
      'powerpc64-linux'        => ['powerpc64', 'linux',     nil],
      'sparc-solaris2.10'      => ['sparc',     'solaris',   '2.10'],
      'sparc-solaris2.8'       => ['sparc',     'solaris',   '2.8'],
      'sparc-solaris2.9'       => ['sparc',     'solaris',   '2.9'],
      'universal-darwin8'      => ['universal', 'darwin',    '8'],
      'universal-darwin9'      => ['universal', 'darwin',    '9'],
      'universal-macruby'      => ['universal', 'macruby',   nil],
      'i386-cygwin'            => ['x86',       'cygwin',    nil],
      'i686-darwin'            => ['x86',       'darwin',    nil],
      'i686-darwin8.4.1'       => ['x86',       'darwin',    '8'],
      'i386-freebsd4.11'       => ['x86',       'freebsd',   '4'],
      'i386-freebsd5'          => ['x86',       'freebsd',   '5'],
      'i386-freebsd6'          => ['x86',       'freebsd',   '6'],
      'i386-freebsd7'          => ['x86',       'freebsd',   '7'],
      'i386-freebsd'           => ['x86',       'freebsd',   nil],
      'universal-freebsd'      => ['universal', 'freebsd',   nil],
      'i386-java1.5'           => ['x86',       'java',      '1.5'],
      'x86-java1.6'            => ['x86',       'java',      '1.6'],
      'i386-java1.6'           => ['x86',       'java',      '1.6'],
      'i686-linux'             => ['x86',       'linux',     nil],
      'i586-linux'             => ['x86',       'linux',     nil],
      'i486-linux'             => ['x86',       'linux',     nil],
      'i386-linux'             => ['x86',       'linux',     nil],
      'i586-linux-gnu'         => ['x86',       'linux',     nil],
      'i386-linux-gnu'         => ['x86',       'linux',     nil],
      'i386-mingw32'           => ['x86',       'mingw32',   nil],
      'i386-mswin32'           => ['x86',       'mswin32',   nil],
      'i386-mswin32_80'        => ['x86',       'mswin32',   '80'],
      'i386-mswin32-80'        => ['x86',       'mswin32',   '80'],
      'x86-mswin32'            => ['x86',       'mswin32',   nil],
      'x86-mswin32_60'         => ['x86',       'mswin32',   '60'],
      'x86-mswin32-60'         => ['x86',       'mswin32',   '60'],
      'i386-netbsdelf'         => ['x86',       'netbsdelf', nil],
      'i386-openbsd4.0'        => ['x86',       'openbsd',   '4.0'],
      'i386-solaris2.10'       => ['x86',       'solaris',   '2.10'],
      'i386-solaris2.8'        => ['x86',       'solaris',   '2.8'],
      'mswin32'                => ['x86',       'mswin32',   nil],
      'x86_64-linux'           => ['x86_64',    'linux',     nil],
      'x86_64-linux-musl'      => ['x86_64',    'linux',     'musl'],
      'x86_64-openbsd3.9'      => ['x86_64',    'openbsd',   '3.9'],
      'x86_64-openbsd4.0'      => ['x86_64',    'openbsd',   '4.0'],
      'x86_64-openbsd'         => ['x86_64',    'openbsd',   nil],
    }

    test_cases.each do |arch, expected|
      platform = Gem::Platform.new arch
      assert_equal expected, platform.to_a, arch.inspect
    end
  end

  def test_initialize_command_line
    expected = ['x86', 'mswin32', nil]

    platform = Gem::Platform.new 'i386-mswin32'

    assert_equal expected, platform.to_a, 'i386-mswin32'

    expected = ['x86', 'mswin32', '80']

    platform = Gem::Platform.new 'i386-mswin32-80'

    assert_equal expected, platform.to_a, 'i386-mswin32-80'

    expected = ['x86', 'solaris', '2.10']

    platform = Gem::Platform.new 'i386-solaris-2.10'

    assert_equal expected, platform.to_a, 'i386-solaris-2.10'
  end

  def test_initialize_mswin32_vc6
    orig_RUBY_SO_NAME = RbConfig::CONFIG['RUBY_SO_NAME']
    RbConfig::CONFIG['RUBY_SO_NAME'] = 'msvcrt-ruby18'

    expected = ['x86', 'mswin32', nil]

    platform = Gem::Platform.new 'i386-mswin32'

    assert_equal expected, platform.to_a, 'i386-mswin32 VC6'
  ensure
    if orig_RUBY_SO_NAME
      RbConfig::CONFIG['RUBY_SO_NAME'] = orig_RUBY_SO_NAME
    else
      RbConfig::CONFIG.delete 'RUBY_SO_NAME'
    end
  end

  def test_initialize_platform
    platform = Gem::Platform.new 'cpu-my_platform1'

    assert_equal 'cpu', platform.cpu
    assert_equal 'my_platform', platform.os
    assert_equal '1', platform.version
  end

  def test_initialize_test
    platform = Gem::Platform.new 'cpu-my_platform1'
    assert_equal 'cpu', platform.cpu
    assert_equal 'my_platform', platform.os
    assert_equal '1', platform.version

    platform = Gem::Platform.new 'cpu-other_platform1'
    assert_equal 'cpu', platform.cpu
    assert_equal 'other_platform', platform.os
    assert_equal '1', platform.version
  end

  def test_to_s
    if win_platform?
      assert_equal 'x86-mswin32-60', Gem::Platform.local.to_s
    else
      assert_equal 'x86-darwin-8', Gem::Platform.local.to_s
    end
  end

  def test_equals2
    my = Gem::Platform.new %w[cpu my_platform 1]
    other = Gem::Platform.new %w[cpu other_platform 1]

    assert_equal my, my
    refute_equal my, other
    refute_equal other, my
  end

  def test_equals3
    my = Gem::Platform.new %w[cpu my_platform 1]
    other = Gem::Platform.new %w[cpu other_platform 1]

    assert(my === my)
    refute(other === my)
    refute(my === other)
  end

  def test_equals3_cpu
    ppc_darwin8 = Gem::Platform.new 'powerpc-darwin8.0'
    uni_darwin8 = Gem::Platform.new 'universal-darwin8.0'
    x86_darwin8 = Gem::Platform.new 'i686-darwin8.0'

    util_set_arch 'powerpc-darwin8'
    assert((ppc_darwin8 === Gem::Platform.local), 'powerpc =~ universal')
    assert((uni_darwin8 === Gem::Platform.local), 'powerpc =~ universal')
    refute((x86_darwin8 === Gem::Platform.local), 'powerpc =~ universal')

    util_set_arch 'i686-darwin8'
    refute((ppc_darwin8 === Gem::Platform.local), 'powerpc =~ universal')
    assert((uni_darwin8 === Gem::Platform.local), 'x86 =~ universal')
    assert((x86_darwin8 === Gem::Platform.local), 'powerpc =~ universal')

    util_set_arch 'universal-darwin8'
    assert((ppc_darwin8 === Gem::Platform.local), 'universal =~ ppc')
    assert((uni_darwin8 === Gem::Platform.local), 'universal =~ universal')
    assert((x86_darwin8 === Gem::Platform.local), 'universal =~ x86')
  end

  def test_nil_cpu_arch_is_treated_as_universal
    with_nil_arch = Gem::Platform.new [nil, 'mingw32']
    with_uni_arch = Gem::Platform.new ['universal', 'mingw32']
    with_x86_arch = Gem::Platform.new ['x86', 'mingw32']

    assert((with_nil_arch === with_uni_arch), 'nil =~ universal')
    assert((with_uni_arch === with_nil_arch), 'universal =~ nil')
    assert((with_nil_arch === with_x86_arch), 'nil =~ x86')
    assert((with_x86_arch === with_nil_arch), 'x86 =~ nil')
  end

  def test_equals3_cpu_arm
    arm   = Gem::Platform.new 'arm-linux'
    armv5 = Gem::Platform.new 'armv5-linux'
    armv7 = Gem::Platform.new 'armv7-linux'

    util_set_arch 'armv5-linux'
    assert((arm   === Gem::Platform.local), 'arm   === armv5')
    assert((armv5 === Gem::Platform.local), 'armv5 === armv5')
    refute((armv7 === Gem::Platform.local), 'armv7 === armv5')
    refute((Gem::Platform.local === arm), 'armv5 === arm')

    util_set_arch 'armv7-linux'
    assert((arm   === Gem::Platform.local), 'arm   === armv7')
    refute((armv5 === Gem::Platform.local), 'armv5 === armv7')
    assert((armv7 === Gem::Platform.local), 'armv7 === armv7')
    refute((Gem::Platform.local === arm), 'armv7 === arm')
  end

  def test_equals3_version
    util_set_arch 'i686-darwin8'

    x86_darwin = Gem::Platform.new ['x86', 'darwin', nil]
    x86_darwin7 = Gem::Platform.new ['x86', 'darwin', '7']
    x86_darwin8 = Gem::Platform.new ['x86', 'darwin', '8']
    x86_darwin9 = Gem::Platform.new ['x86', 'darwin', '9']

    assert((x86_darwin  === Gem::Platform.local), 'x86_darwin === x86_darwin8')
    assert((x86_darwin8 === Gem::Platform.local), 'x86_darwin8 === x86_darwin8')

    refute((x86_darwin7 === Gem::Platform.local), 'x86_darwin7 === x86_darwin8')
    refute((x86_darwin9 === Gem::Platform.local), 'x86_darwin9 === x86_darwin8')
  end

  def test_equals_tilde
    util_set_arch 'i386-mswin32'

    assert_local_match 'mswin32'
    assert_local_match 'i386-mswin32'

    # oddballs
    assert_local_match 'i386-mswin32-mq5.3'
    assert_local_match 'i386-mswin32-mq6'
    refute_local_match 'win32-1.8.2-VC7'
    refute_local_match 'win32-1.8.4-VC6'
    refute_local_match 'win32-source'
    refute_local_match 'windows'

    util_set_arch 'i686-linux'
    assert_local_match 'i486-linux'
    assert_local_match 'i586-linux'
    assert_local_match 'i686-linux'

    util_set_arch 'i686-darwin8'
    assert_local_match 'i686-darwin8.4.1'
    assert_local_match 'i686-darwin8.8.2'

    util_set_arch 'java'
    assert_local_match 'java'
    assert_local_match 'jruby'

    util_set_arch 'universal-dotnet2.0'
    assert_local_match 'universal-dotnet'
    assert_local_match 'universal-dotnet-2.0'
    refute_local_match 'universal-dotnet-4.0'
    assert_local_match 'dotnet'
    assert_local_match 'dotnet-2.0'
    refute_local_match 'dotnet-4.0'

    util_set_arch 'universal-dotnet4.0'
    assert_local_match 'universal-dotnet'
    refute_local_match 'universal-dotnet-2.0'
    assert_local_match 'universal-dotnet-4.0'
    assert_local_match 'dotnet'
    refute_local_match 'dotnet-2.0'
    assert_local_match 'dotnet-4.0'

    util_set_arch 'universal-macruby-1.0'
    assert_local_match 'universal-macruby'
    assert_local_match 'macruby'
    refute_local_match 'universal-macruby-0.10'
    assert_local_match 'universal-macruby-1.0'

    util_set_arch 'powerpc-darwin'
    assert_local_match 'powerpc-darwin'

    util_set_arch 'powerpc-darwin7'
    assert_local_match 'powerpc-darwin7.9.0'

    util_set_arch 'powerpc-darwin8'
    assert_local_match 'powerpc-darwin8.10.0'

    util_set_arch 'sparc-solaris2.8'
    assert_local_match 'sparc-solaris2.8-mq5.3'
  end

  def test_inspect
    result = Gem::Platform.new("universal-java11").inspect

    assert_equal 1, result.scan(/@cpu=/).size
    assert_equal 1, result.scan(/@os=/).size
    assert_equal 1, result.scan(/@version=/).size
  end

  def assert_local_match(name)
    assert_match Gem::Platform.local, name
  end

  def refute_local_match(name)
    refute_match Gem::Platform.local, name
  end
end
