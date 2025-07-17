# frozen_string_literal: true

require_relative "helper"
require "rubygems/platform"
require "rbconfig"

class TestGemPlatform < Gem::TestCase
  def test_self_local
    util_set_arch "i686-darwin8.10.1"

    assert_equal Gem::Platform.new(%w[x86 darwin 8]), Gem::Platform.local
  end

  def test_self_match
    Gem::Deprecate.skip_during do
      assert Gem::Platform.match(nil), "nil == ruby"
      assert Gem::Platform.match(Gem::Platform.local), "exact match"
      assert Gem::Platform.match(Gem::Platform.local.to_s), "=~ match"
      assert Gem::Platform.match(Gem::Platform::RUBY), "ruby"
    end
  end

  def test_self_match_gem?
    assert Gem::Platform.match_gem?(nil, "json"), "nil == ruby"
    assert Gem::Platform.match_gem?(Gem::Platform.local, "json"), "exact match"
    assert Gem::Platform.match_gem?(Gem::Platform.local.to_s, "json"), "=~ match"
    assert Gem::Platform.match_gem?(Gem::Platform::RUBY, "json"), "ruby"
  end

  def test_self_match_spec?
    make_spec = ->(platform) do
      util_spec "mygem-for-platform-match_spec", "1" do |s|
        s.platform = platform
      end
    end

    assert Gem::Platform.match_spec?(make_spec.call(nil)), "nil == ruby"
    assert Gem::Platform.match_spec?(make_spec.call(Gem::Platform.local)), "exact match"
    assert Gem::Platform.match_spec?(make_spec.call(Gem::Platform.local.to_s)), "=~ match"
    assert Gem::Platform.match_spec?(make_spec.call(Gem::Platform::RUBY)), "ruby"
  end

  def test_self_match_spec_with_match_gem_override
    make_spec = ->(name, platform) do
      util_spec name, "1" do |s|
        s.platform = platform
      end
    end

    class << Gem::Platform
      alias_method :original_match_gem?, :match_gem?
      def match_gem?(platform, gem_name)
        # e.g., sassc and libv8 are such gems, their native extensions do not use the Ruby C API
        if gem_name == "gem-with-ruby-impl-independent-precompiled-ext"
          match_platforms?(platform, [Gem::Platform::RUBY, Gem::Platform.local])
        else
          match_platforms?(platform, Gem.platforms)
        end
      end
    end

    platforms = Gem.platforms
    Gem.platforms = [Gem::Platform::RUBY]
    begin
      assert_equal true,  Gem::Platform.match_spec?(make_spec.call("mygem", Gem::Platform::RUBY))
      assert_equal false, Gem::Platform.match_spec?(make_spec.call("mygem", Gem::Platform.local))

      name = "gem-with-ruby-impl-independent-precompiled-ext"
      assert_equal true, Gem::Platform.match_spec?(make_spec.call(name, Gem::Platform.local))
    ensure
      Gem.platforms = platforms
      class << Gem::Platform
        remove_method :match_gem?
        alias_method :match_gem?, :original_match_gem?
        remove_method :original_match_gem?
      end
    end
  end

  def test_self_new
    assert_equal Gem::Platform.local, Gem::Platform.new(Gem::Platform::CURRENT)
    assert_equal Gem::Platform::RUBY, Gem::Platform.new(Gem::Platform::RUBY)
    assert_equal Gem::Platform::RUBY, Gem::Platform.new(nil)
    assert_equal Gem::Platform::RUBY, Gem::Platform.new("")
  end

  def test_initialize
    test_cases = {
      "amd64-freebsd6" => ["amd64", "freebsd", "6"],
      "java" => [nil, "java", nil],
      "jruby" => [nil, "java", nil],
      "universal-dotnet" => ["universal", "dotnet", nil],
      "universal-dotnet2.0" => ["universal", "dotnet", "2.0"],
      "universal-dotnet4.0" => ["universal", "dotnet", "4.0"],
      "powerpc-aix5.3.0.0" => ["powerpc", "aix", "5"],
      "powerpc-darwin7" => ["powerpc", "darwin", "7"],
      "powerpc-darwin8" => ["powerpc", "darwin", "8"],
      "powerpc-linux" => ["powerpc", "linux", nil],
      "powerpc64-linux" => ["powerpc64", "linux", nil],
      "sparc-solaris2.10" => ["sparc", "solaris", "2.10"],
      "sparc-solaris2.8" => ["sparc", "solaris", "2.8"],
      "sparc-solaris2.9" => ["sparc", "solaris", "2.9"],
      "universal-darwin8" => ["universal", "darwin", "8"],
      "universal-darwin9" => ["universal", "darwin", "9"],
      "universal-macruby" => ["universal", "macruby", nil],
      "i386-cygwin" => ["x86", "cygwin", nil],
      "i686-darwin" => ["x86", "darwin", nil],
      "i686-darwin8.4.1" => ["x86", "darwin", "8"],
      "i386-freebsd4.11" => ["x86", "freebsd", "4"],
      "i386-freebsd5" => ["x86", "freebsd", "5"],
      "i386-freebsd6" => ["x86", "freebsd", "6"],
      "i386-freebsd7" => ["x86", "freebsd", "7"],
      "i386-freebsd" => ["x86", "freebsd", nil],
      "universal-freebsd" => ["universal", "freebsd", nil],
      "i386-java1.5" => ["x86", "java", "1.5"],
      "x86-java1.6" => ["x86", "java", "1.6"],
      "i386-java1.6" => ["x86", "java", "1.6"],
      "i686-linux" => ["x86", "linux", nil],
      "i586-linux" => ["x86", "linux", nil],
      "i486-linux" => ["x86", "linux", nil],
      "i386-linux" => ["x86", "linux", nil],
      "i586-linux-gnu" => ["x86", "linux", "gnu"],
      "i386-linux-gnu" => ["x86", "linux", "gnu"],
      "i386-mingw32" => ["x86", "mingw32", nil],
      "x64-mingw-ucrt" => ["x64", "mingw", "ucrt"],
      "i386-mswin32" => ["x86", "mswin32", nil],
      "i386-mswin32_80" => ["x86", "mswin32", "80"],
      "i386-mswin32-80" => ["x86", "mswin32", "80"],
      "x86-mswin32" => ["x86", "mswin32", nil],
      "x86-mswin32_60" => ["x86", "mswin32", "60"],
      "x86-mswin32-60" => ["x86", "mswin32", "60"],
      "i386-netbsdelf" => ["x86", "netbsdelf", nil],
      "i386-openbsd4.0" => ["x86", "openbsd", "4.0"],
      "i386-solaris2.10" => ["x86", "solaris", "2.10"],
      "i386-solaris2.8" => ["x86", "solaris", "2.8"],
      "mswin32" => ["x86", "mswin32", nil],
      "x86_64-linux" => ["x86_64", "linux", nil],
      "x86_64-linux-gnu" => ["x86_64", "linux", "gnu"],
      "x86_64-linux-musl" => ["x86_64", "linux", "musl"],
      "x86_64-linux-uclibc" => ["x86_64", "linux", "uclibc"],
      "arm-linux-eabi" => ["arm", "linux", "eabi"],
      "arm-linux-gnueabi" => ["arm", "linux", "gnueabi"],
      "arm-linux-musleabi" => ["arm", "linux", "musleabi"],
      "arm-linux-uclibceabi" => ["arm", "linux", "uclibceabi"],
      "x86_64-openbsd3.9" => ["x86_64", "openbsd", "3.9"],
      "x86_64-openbsd4.0" => ["x86_64", "openbsd", "4.0"],
      "x86_64-openbsd" => ["x86_64", "openbsd", nil],
      "wasm32-wasi" => ["wasm32", "wasi", nil],
      "wasm32-wasip1" => ["wasm32", "wasi", nil],
      "wasm32-wasip2" => ["wasm32", "wasi", nil],

      "darwin-java-java" => ["darwin", "java", nil],
      "linux-linux-linux" => ["linux", "linux", "linux"],
      "linux-linux-linux1.0" => ["linux", "linux", "linux1"],
      "x86x86-1x86x86x86x861linuxx86x86" => ["x86x86", "linux", "x86x86"],
      "freebsd0" => [nil, "freebsd", "0"],
      "darwin0" => [nil, "darwin", "0"],
      "darwin0---" => [nil, "darwin", "0"],
      "x86-linux-x8611.0l" => ["x86", "linux", "x8611"],
      "0-x86linuxx86---" => ["0", "linux", "x86"],
      "x86_64-macruby-x86" => ["x86_64", "macruby", nil],
      "x86_64-dotnetx86" => ["x86_64", "dotnet", nil],
      "x86_64-dalvik0" => ["x86_64", "dalvik", "0"],
      "x86_64-dotnet1." => ["x86_64", "dotnet", "1"],

      "--" => [nil, "unknown", nil],
    }

    test_cases.each do |arch, expected|
      platform = Gem::Platform.new arch
      assert_equal expected, platform.to_a, arch.inspect
      platform2 = Gem::Platform.new platform.to_s
      assert_equal expected, platform2.to_a, "#{arch.inspect} => #{platform2.inspect}"
    end
  end

  def test_initialize_command_line
    expected = ["x86", "mswin32", nil]

    platform = Gem::Platform.new "i386-mswin32"

    assert_equal expected, platform.to_a, "i386-mswin32"

    expected = ["x86", "mswin32", "80"]

    platform = Gem::Platform.new "i386-mswin32-80"

    assert_equal expected, platform.to_a, "i386-mswin32-80"

    expected = ["x86", "solaris", "2.10"]

    platform = Gem::Platform.new "i386-solaris-2.10"

    assert_equal expected, platform.to_a, "i386-solaris-2.10"
  end

  def test_initialize_mswin32_vc6
    orig_ruby_so_name = RbConfig::CONFIG["RUBY_SO_NAME"]
    RbConfig::CONFIG["RUBY_SO_NAME"] = "msvcrt-ruby18"

    expected = ["x86", "mswin32", nil]

    platform = Gem::Platform.new "i386-mswin32"

    assert_equal expected, platform.to_a, "i386-mswin32 VC6"
  ensure
    if orig_ruby_so_name
      RbConfig::CONFIG["RUBY_SO_NAME"] = orig_ruby_so_name
    else
      RbConfig::CONFIG.delete "RUBY_SO_NAME"
    end
  end

  def test_initialize_platform
    platform = Gem::Platform.new "cpu-my_platform1"

    assert_equal "cpu", platform.cpu
    assert_equal "my_platform", platform.os
    assert_equal "1", platform.version
  end

  def test_initialize_test
    platform = Gem::Platform.new "cpu-my_platform1"
    assert_equal "cpu", platform.cpu
    assert_equal "my_platform", platform.os
    assert_equal "1", platform.version

    platform = Gem::Platform.new "cpu-other_platform1"
    assert_equal "cpu", platform.cpu
    assert_equal "other_platform", platform.os
    assert_equal "1", platform.version
  end

  def test_to_s
    if Gem.win_platform?
      assert_equal "x86-mswin32-60", Gem::Platform.local.to_s
    else
      assert_equal "x86-darwin-8", Gem::Platform.local.to_s
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

    assert(my === my) # rubocop:disable Lint/BinaryOperatorWithIdenticalOperands
    refute(other === my)
    refute(my === other)
  end

  def test_equals3_cpu
    ppc_darwin8 = Gem::Platform.new "powerpc-darwin8.0"
    uni_darwin8 = Gem::Platform.new "universal-darwin8.0"
    x86_darwin8 = Gem::Platform.new "i686-darwin8.0"

    util_set_arch "powerpc-darwin8"
    assert((ppc_darwin8 === Gem::Platform.local), "powerpc =~ universal")
    assert((uni_darwin8 === Gem::Platform.local), "powerpc =~ universal")
    refute((x86_darwin8 === Gem::Platform.local), "powerpc =~ universal")

    util_set_arch "i686-darwin8"
    refute((ppc_darwin8 === Gem::Platform.local), "powerpc =~ universal")
    assert((uni_darwin8 === Gem::Platform.local), "x86 =~ universal")
    assert((x86_darwin8 === Gem::Platform.local), "powerpc =~ universal")

    util_set_arch "universal-darwin8"
    assert((ppc_darwin8 === Gem::Platform.local), "universal =~ ppc")
    assert((uni_darwin8 === Gem::Platform.local), "universal =~ universal")
    assert((x86_darwin8 === Gem::Platform.local), "universal =~ x86")
  end

  def test_nil_cpu_arch_is_treated_as_universal
    with_nil_arch = Gem::Platform.new [nil, "mingw32"]
    with_uni_arch = Gem::Platform.new ["universal", "mingw32"]
    with_x86_arch = Gem::Platform.new ["x86", "mingw32"]

    assert((with_nil_arch === with_uni_arch), "nil =~ universal")
    assert((with_uni_arch === with_nil_arch), "universal =~ nil")
    assert((with_nil_arch === with_x86_arch), "nil =~ x86")
    assert((with_x86_arch === with_nil_arch), "x86 =~ nil")
  end

  def test_nil_version_is_treated_as_any_version
    x86_darwin_8 = Gem::Platform.new "i686-darwin8.0"
    x86_darwin_nil = Gem::Platform.new "i686-darwin"

    assert((x86_darwin_8 === x86_darwin_nil), "8.0 =~ nil")
    assert((x86_darwin_nil === x86_darwin_8), "nil =~ 8.0")
  end

  def test_nil_version_is_stricter_for_linux_os
    x86_linux = Gem::Platform.new "i686-linux"
    x86_linux_gnu = Gem::Platform.new "i686-linux-gnu"
    x86_linux_musl = Gem::Platform.new "i686-linux-musl"
    x86_linux_uclibc = Gem::Platform.new "i686-linux-uclibc"

    # a naked linux runtime is implicit gnu, as it represents the common glibc-linked runtime
    assert(x86_linux === x86_linux_gnu, "linux =~ linux-gnu")
    assert(x86_linux_gnu === x86_linux, "linux-gnu =~ linux")

    # musl and explicit gnu should differ
    refute(x86_linux_gnu === x86_linux_musl, "linux-gnu =~ linux-musl")
    refute(x86_linux_musl === x86_linux_gnu, "linux-musl =~ linux-gnu")

    # explicit libc differ
    refute(x86_linux_uclibc === x86_linux_musl, "linux-uclibc =~ linux-musl")
    refute(x86_linux_musl === x86_linux_uclibc, "linux-musl =~ linux-uclibc")

    # musl host runtime accepts libc-generic or statically linked gems...
    assert(x86_linux === x86_linux_musl, "linux =~ linux-musl")
    # ...but implicit gnu runtime generally does not accept musl-specific gems
    refute(x86_linux_musl === x86_linux, "linux-musl =~ linux")

    # other libc are not glibc compatible
    refute(x86_linux === x86_linux_uclibc, "linux =~ linux-uclibc")
    refute(x86_linux_uclibc === x86_linux, "linux-uclibc =~ linux")
  end

  def test_eabi_version_is_stricter_for_linux_os
    arm_linux_eabi = Gem::Platform.new "arm-linux-eabi"
    arm_linux_gnueabi = Gem::Platform.new "arm-linux-gnueabi"
    arm_linux_musleabi = Gem::Platform.new "arm-linux-musleabi"
    arm_linux_uclibceabi = Gem::Platform.new "arm-linux-uclibceabi"

    # a naked linux runtime is implicit gnu, as it represents the common glibc-linked runtime
    assert(arm_linux_eabi === arm_linux_gnueabi, "linux-eabi =~ linux-gnueabi")
    assert(arm_linux_gnueabi === arm_linux_eabi, "linux-gnueabi =~ linux-eabi")

    # musl and explicit gnu should differ
    refute(arm_linux_gnueabi === arm_linux_musleabi, "linux-gnueabi =~ linux-musleabi")
    refute(arm_linux_musleabi === arm_linux_gnueabi, "linux-musleabi =~ linux-gnueabi")

    # explicit libc differ
    refute(arm_linux_uclibceabi === arm_linux_musleabi, "linux-uclibceabi =~ linux-musleabi")
    refute(arm_linux_musleabi === arm_linux_uclibceabi, "linux-musleabi =~ linux-uclibceabi")

    # musl host runtime accepts libc-generic or statically linked gems...
    assert(arm_linux_eabi === arm_linux_musleabi, "linux-eabi =~ linux-musleabi")
    # ...but implicit gnu runtime generally does not accept musl-specific gems
    refute(arm_linux_musleabi === arm_linux_eabi, "linux-musleabi =~ linux-eabi")

    # other libc are not glibc compatible
    refute(arm_linux_eabi === arm_linux_uclibceabi, "linux-eabi =~ linux-uclibceabi")
    refute(arm_linux_uclibceabi === arm_linux_eabi, "linux-uclibceabi =~ linux-eabi")
  end

  def test_eabi_and_nil_version_combination_strictness
    arm_linux = Gem::Platform.new "arm-linux"
    arm_linux_eabi = Gem::Platform.new "arm-linux-eabi"
    arm_linux_eabihf = Gem::Platform.new "arm-linux-eabihf"
    arm_linux_gnueabi = Gem::Platform.new "arm-linux-gnueabi"
    arm_linux_gnueabihf = Gem::Platform.new "arm-linux-gnueabihf"
    arm_linux_musleabi = Gem::Platform.new "arm-linux-musleabi"
    arm_linux_musleabihf = Gem::Platform.new "arm-linux-musleabihf"
    arm_linux_uclibceabi = Gem::Platform.new "arm-linux-uclibceabi"
    arm_linux_uclibceabihf = Gem::Platform.new "arm-linux-uclibceabihf"

    # generic arm host runtime with eabi modifier accepts generic arm gems
    assert(arm_linux === arm_linux_eabi, "arm-linux =~ arm-linux-eabi")
    assert(arm_linux === arm_linux_eabihf, "arm-linux =~ arm-linux-eabihf")

    # explicit gnu arm host runtime with eabi modifier accepts generic arm gems
    assert(arm_linux === arm_linux_gnueabi, "arm-linux =~ arm-linux-gnueabi")
    assert(arm_linux === arm_linux_gnueabihf, "arm-linux =~ arm-linux-gnueabihf")

    # musl arm host runtime accepts libc-generic or statically linked gems...
    assert(arm_linux === arm_linux_musleabi, "arm-linux =~ arm-linux-musleabi")
    assert(arm_linux === arm_linux_musleabihf, "arm-linux =~ arm-linux-musleabihf")

    # other libc arm hosts are not glibc compatible
    refute(arm_linux === arm_linux_uclibceabi, "arm-linux =~ arm-linux-uclibceabi")
    refute(arm_linux === arm_linux_uclibceabihf, "arm-linux =~ arm-linux-uclibceabihf")
  end

  def test_equals3_cpu_arm
    arm   = Gem::Platform.new "arm-linux"
    armv5 = Gem::Platform.new "armv5-linux"
    armv7 = Gem::Platform.new "armv7-linux"
    arm64 = Gem::Platform.new "arm64-linux"

    util_set_arch "armv5-linux"
    assert((arm   === Gem::Platform.local), "arm   === armv5")
    assert((armv5 === Gem::Platform.local), "armv5 === armv5")
    refute((armv7 === Gem::Platform.local), "armv7 === armv5")
    refute((arm64 === Gem::Platform.local), "arm64 === armv5")
    refute((Gem::Platform.local === arm), "armv5 === arm")

    util_set_arch "armv7-linux"
    assert((arm   === Gem::Platform.local), "arm   === armv7")
    refute((armv5 === Gem::Platform.local), "armv5 === armv7")
    assert((armv7 === Gem::Platform.local), "armv7 === armv7")
    refute((arm64 === Gem::Platform.local), "arm64 === armv7")
    refute((Gem::Platform.local === arm), "armv7 === arm")

    util_set_arch "arm64-linux"
    refute((arm   === Gem::Platform.local), "arm   === arm64")
    refute((armv5 === Gem::Platform.local), "armv5 === arm64")
    refute((armv7 === Gem::Platform.local), "armv7 === arm64")
    assert((arm64 === Gem::Platform.local), "arm64 === arm64")
  end

  def test_equals3_universal_mingw
    uni_mingw  = Gem::Platform.new "universal-mingw"
    mingw_ucrt = Gem::Platform.new "x64-mingw-ucrt"

    util_set_arch "x64-mingw-ucrt"
    assert((uni_mingw === Gem::Platform.local), "uni_mingw === mingw_ucrt")
    assert((mingw_ucrt === Gem::Platform.local), "mingw_ucrt === mingw_ucrt")
  end

  def test_equals3_version
    util_set_arch "i686-darwin8"

    x86_darwin = Gem::Platform.new ["x86", "darwin", nil]
    x86_darwin7 = Gem::Platform.new ["x86", "darwin", "7"]
    x86_darwin8 = Gem::Platform.new ["x86", "darwin", "8"]
    x86_darwin9 = Gem::Platform.new ["x86", "darwin", "9"]

    assert((x86_darwin  === Gem::Platform.local), "x86_darwin === x86_darwin8")
    assert((x86_darwin8 === Gem::Platform.local), "x86_darwin8 === x86_darwin8")

    refute((x86_darwin7 === Gem::Platform.local), "x86_darwin7 === x86_darwin8")
    refute((x86_darwin9 === Gem::Platform.local), "x86_darwin9 === x86_darwin8")
  end

  def test_equals_tilde
    util_set_arch "i386-mswin32"

    assert_local_match "mswin32"
    assert_local_match "i386-mswin32"

    # oddballs
    assert_local_match "i386-mswin32-mq5.3"
    assert_local_match "i386-mswin32-mq6"
    refute_local_match "win32-1.8.2-VC7"
    refute_local_match "win32-1.8.4-VC6"
    refute_local_match "win32-source"
    refute_local_match "windows"

    util_set_arch "i686-linux"
    assert_local_match "i486-linux"
    assert_local_match "i586-linux"
    assert_local_match "i686-linux"

    util_set_arch "i686-darwin8"
    assert_local_match "i686-darwin8.4.1"
    assert_local_match "i686-darwin8.8.2"

    util_set_arch "java"
    assert_local_match "java"
    assert_local_match "jruby"

    util_set_arch "universal-dotnet2.0"
    assert_local_match "universal-dotnet"
    assert_local_match "universal-dotnet-2.0"
    refute_local_match "universal-dotnet-4.0"
    assert_local_match "dotnet"
    assert_local_match "dotnet-2.0"
    refute_local_match "dotnet-4.0"

    util_set_arch "universal-dotnet4.0"
    assert_local_match "universal-dotnet"
    refute_local_match "universal-dotnet-2.0"
    assert_local_match "universal-dotnet-4.0"
    assert_local_match "dotnet"
    refute_local_match "dotnet-2.0"
    assert_local_match "dotnet-4.0"

    util_set_arch "universal-macruby-1.0"
    assert_local_match "universal-macruby"
    assert_local_match "macruby"
    refute_local_match "universal-macruby-0.10"
    assert_local_match "universal-macruby-1.0"

    util_set_arch "powerpc-darwin"
    assert_local_match "powerpc-darwin"

    util_set_arch "powerpc-darwin7"
    assert_local_match "powerpc-darwin7.9.0"

    util_set_arch "powerpc-darwin8"
    assert_local_match "powerpc-darwin8.10.0"

    util_set_arch "sparc-solaris2.8"
    assert_local_match "sparc-solaris2.8-mq5.3"
  end

  def test_inspect
    result = Gem::Platform.new("universal-java11").inspect

    assert_equal 1, result.scan(/@cpu=/).size
    assert_equal 1, result.scan(/@os=/).size
    assert_equal 1, result.scan(/@version=/).size
  end

  def test_gem_platform_match_with_string_argument
    util_set_arch "x86_64-linux-musl"

    Gem::Deprecate.skip_during do
      assert(Gem::Platform.match(Gem::Platform.new("x86_64-linux")), "should match Gem::Platform")
      assert(Gem::Platform.match("x86_64-linux"), "should match String platform")
    end
  end

  def test_constants
    assert_equal [nil, "java", nil], Gem::Platform::JAVA.to_a
    assert_equal ["x86", "mswin32", nil], Gem::Platform::MSWIN.to_a
    assert_equal [nil, "mswin64", nil], Gem::Platform::MSWIN64.to_a
    assert_equal ["x86", "mingw32", nil], Gem::Platform::MINGW.to_a
    assert_equal ["x64", "mingw", "ucrt"], Gem::Platform::X64_MINGW.to_a
    assert_equal ["universal", "mingw", nil], Gem::Platform::UNIVERSAL_MINGW.to_a
    assert_equal [["x86", "mswin32", nil], [nil, "mswin64", nil], ["universal", "mingw", nil]], Gem::Platform::WINDOWS.map(&:to_a)
    assert_equal ["x86_64", "linux", nil], Gem::Platform::X64_LINUX.to_a
    assert_equal ["x86_64", "linux", "musl"], Gem::Platform::X64_LINUX_MUSL.to_a
  end

  def test_generic
    # converts non-windows platforms into ruby
    assert_equal Gem::Platform::RUBY, Gem::Platform.generic(Gem::Platform.new("x86-darwin-10"))
    assert_equal Gem::Platform::RUBY, Gem::Platform.generic(Gem::Platform::RUBY)

    # converts java platform variants into java
    assert_equal Gem::Platform::JAVA, Gem::Platform.generic(Gem::Platform.new("java"))
    assert_equal Gem::Platform::JAVA, Gem::Platform.generic(Gem::Platform.new("universal-java-17"))

    # converts mswin platform variants into x86-mswin32
    assert_equal Gem::Platform::MSWIN, Gem::Platform.generic(Gem::Platform.new("mswin32"))
    assert_equal Gem::Platform::MSWIN, Gem::Platform.generic(Gem::Platform.new("i386-mswin32"))
    assert_equal Gem::Platform::MSWIN, Gem::Platform.generic(Gem::Platform.new("x86-mswin32"))

    # converts 32-bit mingw platform variants into universal-mingw
    assert_equal Gem::Platform::UNIVERSAL_MINGW, Gem::Platform.generic(Gem::Platform.new("i386-mingw32"))
    assert_equal Gem::Platform::UNIVERSAL_MINGW, Gem::Platform.generic(Gem::Platform.new("x86-mingw32"))

    # converts 64-bit mingw platform variants into universal-mingw
    assert_equal Gem::Platform::UNIVERSAL_MINGW, Gem::Platform.generic(Gem::Platform.new("x64-mingw32"))

    # converts x64 mingw UCRT platform variants into universal-mingw
    assert_equal Gem::Platform::UNIVERSAL_MINGW, Gem::Platform.generic(Gem::Platform.new("x64-mingw-ucrt"))

    # converts aarch64 mingw UCRT platform variants into universal-mingw
    assert_equal Gem::Platform::UNIVERSAL_MINGW, Gem::Platform.generic(Gem::Platform.new("aarch64-mingw-ucrt"))

    assert_equal Gem::Platform::RUBY, Gem::Platform.generic(Gem::Platform.new("unknown"))
    assert_equal Gem::Platform::RUBY, Gem::Platform.generic(nil)
    assert_equal Gem::Platform::MSWIN64, Gem::Platform.generic(Gem::Platform.new("mswin64"))
  end

  def test_platform_specificity_match
    [
      ["ruby", "ruby", -1, -1],
      ["x86_64-linux-musl", "x86_64-linux-musl", -1, -1],
      ["x86_64-linux", "x86_64-linux-musl", 100, 200],
      ["universal-darwin", "x86-darwin", 10, 20],
      ["universal-darwin-19", "x86-darwin", 210, 120],
      ["universal-darwin-19", "universal-darwin-20", 200, 200],
      ["arm-darwin-19", "arm64-darwin-19", 0, 20],
    ].each do |spec_platform, user_platform, s1, s2|
      spec_platform = Gem::Platform.new(spec_platform)
      user_platform = Gem::Platform.new(user_platform)
      assert_equal s1, Gem::Platform.platform_specificity_match(spec_platform, user_platform),
        "Gem::Platform.platform_specificity_match(#{spec_platform.to_s.inspect}, #{user_platform.to_s.inspect})"
      assert_equal s2, Gem::Platform.platform_specificity_match(user_platform, spec_platform),
        "Gem::Platform.platform_specificity_match(#{user_platform.to_s.inspect}, #{spec_platform.to_s.inspect})"
    end
  end

  def test_sort_and_filter_best_platform_match
    a_1 = util_spec "a", "1"
    a_1_java = util_spec "a", "1" do |s|
      s.platform = Gem::Platform::JAVA
    end
    a_1_universal_darwin = util_spec "a", "1" do |s|
      s.platform = Gem::Platform.new("universal-darwin")
    end
    a_1_universal_darwin_19 = util_spec "a", "1" do |s|
      s.platform = Gem::Platform.new("universal-darwin-19")
    end
    a_1_universal_darwin_20 = util_spec "a", "1" do |s|
      s.platform = Gem::Platform.new("universal-darwin-20")
    end
    a_1_arm_darwin_19 = util_spec "a", "1" do |s|
      s.platform = Gem::Platform.new("arm64-darwin-19")
    end
    a_1_x86_darwin = util_spec "a", "1" do |s|
      s.platform = Gem::Platform.new("x86-darwin")
    end
    specs = [a_1, a_1_java, a_1_universal_darwin, a_1_universal_darwin_19, a_1_universal_darwin_20, a_1_arm_darwin_19, a_1_x86_darwin]
    assert_equal [a_1], Gem::Platform.sort_and_filter_best_platform_match(specs, "ruby")
    assert_equal [a_1_java], Gem::Platform.sort_and_filter_best_platform_match(specs, Gem::Platform::JAVA)
    assert_equal [a_1_arm_darwin_19], Gem::Platform.sort_and_filter_best_platform_match(specs, Gem::Platform.new("arm64-darwin-19"))
    assert_equal [a_1_universal_darwin_20], Gem::Platform.sort_and_filter_best_platform_match(specs, Gem::Platform.new("arm64-darwin-20"))
    assert_equal [a_1_universal_darwin_19], Gem::Platform.sort_and_filter_best_platform_match(specs, Gem::Platform.new("x86-darwin-19"))
    assert_equal [a_1_universal_darwin_20], Gem::Platform.sort_and_filter_best_platform_match(specs, Gem::Platform.new("x86-darwin-20"))
    assert_equal [a_1_x86_darwin], Gem::Platform.sort_and_filter_best_platform_match(specs, Gem::Platform.new("x86-darwin-21"))
  end

  def test_sort_best_platform_match
    a_1 = util_spec "a", "1"
    a_1_java = util_spec "a", "1" do |s|
      s.platform = Gem::Platform::JAVA
    end
    a_1_universal_darwin = util_spec "a", "1" do |s|
      s.platform = Gem::Platform.new("universal-darwin")
    end
    a_1_universal_darwin_19 = util_spec "a", "1" do |s|
      s.platform = Gem::Platform.new("universal-darwin-19")
    end
    a_1_universal_darwin_20 = util_spec "a", "1" do |s|
      s.platform = Gem::Platform.new("universal-darwin-20")
    end
    a_1_arm_darwin_19 = util_spec "a", "1" do |s|
      s.platform = Gem::Platform.new("arm64-darwin-19")
    end
    a_1_x86_darwin = util_spec "a", "1" do |s|
      s.platform = Gem::Platform.new("x86-darwin")
    end
    specs = [a_1, a_1_java, a_1_universal_darwin, a_1_universal_darwin_19, a_1_universal_darwin_20, a_1_arm_darwin_19, a_1_x86_darwin]
    assert_equal ["ruby",
                  "java",
                  "universal-darwin",
                  "universal-darwin-19",
                  "universal-darwin-20",
                  "arm64-darwin-19",
                  "x86-darwin"], Gem::Platform.sort_best_platform_match(specs, "ruby").map {|s| s.platform.to_s }
    assert_equal ["java",
                  "universal-darwin",
                  "x86-darwin",
                  "universal-darwin-19",
                  "universal-darwin-20",
                  "arm64-darwin-19",
                  "ruby"], Gem::Platform.sort_best_platform_match(specs, Gem::Platform::JAVA).map {|s| s.platform.to_s }
    assert_equal ["arm64-darwin-19",
                  "universal-darwin-19",
                  "universal-darwin",
                  "java",
                  "x86-darwin",
                  "universal-darwin-20",
                  "ruby"], Gem::Platform.sort_best_platform_match(specs, Gem::Platform.new("arm64-darwin-19")).map {|s| s.platform.to_s }
    assert_equal ["universal-darwin-20",
                  "universal-darwin",
                  "java",
                  "x86-darwin",
                  "arm64-darwin-19",
                  "universal-darwin-19",
                  "ruby"], Gem::Platform.sort_best_platform_match(specs, Gem::Platform.new("arm64-darwin-20")).map {|s| s.platform.to_s }
    assert_equal ["universal-darwin-19",
                  "arm64-darwin-19",
                  "x86-darwin",
                  "universal-darwin",
                  "java",
                  "universal-darwin-20",
                  "ruby"], Gem::Platform.sort_best_platform_match(specs, Gem::Platform.new("x86-darwin-19")).map {|s| s.platform.to_s }
    assert_equal ["universal-darwin-20",
                  "x86-darwin",
                  "universal-darwin",
                  "java",
                  "universal-darwin-19",
                  "arm64-darwin-19",
                  "ruby"], Gem::Platform.sort_best_platform_match(specs, Gem::Platform.new("x86-darwin-20")).map {|s| s.platform.to_s }
    assert_equal ["x86-darwin",
                  "universal-darwin",
                  "java",
                  "universal-darwin-19",
                  "universal-darwin-20",
                  "arm64-darwin-19",
                  "ruby"], Gem::Platform.sort_best_platform_match(specs, Gem::Platform.new("x86-darwin-21")).map {|s| s.platform.to_s }
  end

  def assert_local_match(name)
    assert_match Gem::Platform.local, name
  end

  def refute_local_match(name)
    refute_match Gem::Platform.local, name
  end
end
