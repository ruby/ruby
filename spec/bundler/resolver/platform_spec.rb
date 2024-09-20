# frozen_string_literal: true

RSpec.describe "Resolving platform craziness" do
  describe "with cross-platform gems" do
    before :each do
      @index = an_awesome_index
    end

    it "resolves a simple multi platform gem" do
      dep "nokogiri"
      platforms "ruby", "java"

      should_resolve_as %w[nokogiri-1.4.2 nokogiri-1.4.2-java weakling-0.0.3]
    end

    it "doesn't pull gems that don't exist for the current platform" do
      dep "nokogiri"
      platforms "ruby"

      should_resolve_as %w[nokogiri-1.4.2]
    end

    it "doesn't pull gems when the version is available for all requested platforms" do
      dep "nokogiri"
      platforms "mswin32"

      should_resolve_as %w[nokogiri-1.4.2.1-x86-mswin32]
    end
  end

  it "resolves multiplatform gems with redundant platforms correctly" do
    @index = build_index do
      gem "zookeeper", "1.4.11"
      gem "zookeeper", "1.4.11", "java" do
        dep "slyphon-log4j", "= 1.2.15"
        dep "slyphon-zookeeper_jar", "= 3.3.5"
      end
      gem "slyphon-log4j", "1.2.15"
      gem "slyphon-zookeeper_jar", "3.3.5", "java"
    end

    dep "zookeeper"
    platforms "java", "ruby", "universal-java-11"

    should_resolve_as %w[zookeeper-1.4.11 zookeeper-1.4.11-java slyphon-log4j-1.2.15 slyphon-zookeeper_jar-3.3.5-java]
  end

  it "takes the latest ruby gem, even if an older platform specific version is available" do
    @index = build_index do
      gem "foo", "1.0.0"
      gem "foo", "1.0.0", "x64-mingw32"
      gem "foo", "1.1.0"
    end
    dep "foo"
    platforms "x64-mingw32"

    should_resolve_as %w[foo-1.1.0]
  end

  it "takes the ruby version if the platform version is incompatible" do
    @index = build_index do
      gem "bar", "1.0.0"
      gem "foo", "1.0.0"
      gem "foo", "1.0.0", "x64-mingw32" do
        dep "bar", "< 1"
      end
    end
    dep "foo"
    platforms "x64-mingw32"

    should_resolve_as %w[foo-1.0.0]
  end

  it "prefers the platform specific gem to the ruby version" do
    @index = build_index do
      gem "foo", "1.0.0"
      gem "foo", "1.0.0", "x64-mingw32"
    end
    dep "foo"
    platforms "x64-mingw32"

    should_resolve_as %w[foo-1.0.0-x64-mingw32]
  end

  describe "on a linux platform" do
    # Ruby's platform is *-linux => platform's libc is glibc, so not musl
    # Ruby's platform is *-linux-musl => platform's libc is musl, so not glibc
    # Gem's platform is *-linux => gem is glibc + maybe musl compatible
    # Gem's platform is *-linux-musl => gem is musl compatible but not glibc

    it "favors the platform version-specific gem on a version-specifying linux platform" do
      @index = build_index do
        gem "foo", "1.0.0"
        gem "foo", "1.0.0", "x86_64-linux"
        gem "foo", "1.0.0", "x86_64-linux-musl"
      end
      dep "foo"
      platforms "x86_64-linux-musl"

      should_resolve_as %w[foo-1.0.0-x86_64-linux-musl]
    end

    it "favors the version-less gem over the version-specific gem on a gnu linux platform" do
      @index = build_index do
        gem "foo", "1.0.0"
        gem "foo", "1.0.0", "x86_64-linux"
        gem "foo", "1.0.0", "x86_64-linux-musl"
      end
      dep "foo"
      platforms "x86_64-linux"

      should_resolve_as %w[foo-1.0.0-x86_64-linux]
    end

    it "ignores the platform version-specific gem on a gnu linux platform" do
      @index = build_index do
        gem "foo", "1.0.0", "x86_64-linux-musl"
      end
      dep "foo"
      platforms "x86_64-linux"

      should_not_resolve
    end

    it "falls back to the platform version-less gem on a linux platform with a version" do
      @index = build_index do
        gem "foo", "1.0.0"
        gem "foo", "1.0.0", "x86_64-linux"
      end
      dep "foo"
      platforms "x86_64-linux-musl"

      should_resolve_as %w[foo-1.0.0-x86_64-linux]
    end

    it "falls back to the ruby platform gem on a gnu linux platform when only a version-specifying gem is available" do
      @index = build_index do
        gem "foo", "1.0.0"
        gem "foo", "1.0.0", "x86_64-linux-musl"
      end
      dep "foo"
      platforms "x86_64-linux"

      should_resolve_as %w[foo-1.0.0]
    end

    it "falls back to the platform version-less gem on a version-specifying linux platform and no ruby platform gem is available" do
      @index = build_index do
        gem "foo", "1.0.0", "x86_64-linux"
      end
      dep "foo"
      platforms "x86_64-linux-musl"

      should_resolve_as %w[foo-1.0.0-x86_64-linux]
    end
  end

  context "when the platform specific gem doesn't match the required_ruby_version" do
    before do
      @index = build_index do
        gem "foo", "1.0.0"
        gem "foo", "1.0.0", "x64-mingw32"
        gem "foo", "1.1.0"
        gem "foo", "1.1.0", "x64-mingw32" do |s|
          s.required_ruby_version = [">= 2.0", "< 2.4"]
        end
        gem "Ruby\0", "2.5.1"
      end
      dep "Ruby\0", "2.5.1"
      platforms "x64-mingw32"
    end

    it "takes the latest ruby gem" do
      dep "foo"

      should_resolve_as %w[foo-1.1.0]
    end

    it "takes the latest ruby gem, even if requirement does not match previous versions with the same ruby requirement" do
      dep "foo", "1.1.0"

      should_resolve_as %w[foo-1.1.0]
    end
  end

  it "takes the latest ruby gem with required_ruby_version if the platform specific gem doesn't match the required_ruby_version" do
    @index = build_index do
      gem "foo", "1.0.0"
      gem "foo", "1.0.0", "x64-mingw32"
      gem "foo", "1.1.0" do |s|
        s.required_ruby_version = [">= 2.0"]
      end
      gem "foo", "1.1.0", "x64-mingw32" do |s|
        s.required_ruby_version = [">= 2.0", "< 2.4"]
      end
      gem "Ruby\0", "2.5.1"
    end
    dep "foo"
    dep "Ruby\0", "2.5.1"
    platforms "x64-mingw32"

    should_resolve_as %w[foo-1.1.0]
  end

  it "takes the latest ruby gem if the platform specific gem doesn't match the required_ruby_version with multiple platforms" do
    @index = build_index do
      gem "foo", "1.0.0"
      gem "foo", "1.0.0", "x64-mingw32"
      gem "foo", "1.1.0" do |s|
        s.required_ruby_version = [">= 2.0"]
      end
      gem "foo", "1.1.0", "x64-mingw32" do |s|
        s.required_ruby_version = [">= 2.0", "< 2.4"]
      end
      gem "Ruby\0", "2.5.1"
    end
    dep "foo"
    dep "Ruby\0", "2.5.1"
    platforms "x86_64-linux", "x64-mingw32"

    should_resolve_as %w[foo-1.1.0]
  end

  it "includes gems needed for at least one platform" do
    @index = build_index do
      gem "empyrean", "0.1.0"
      gem "coderay", "1.1.2"
      gem "method_source", "0.9.0"

      gem "spoon", "0.0.6" do
        dep "ffi", ">= 0"
      end

      gem "pry", "0.11.3", "java" do
        dep "coderay", "~> 1.1.0"
        dep "method_source", "~> 0.9.0"
        dep "spoon", "~> 0.0"
      end

      gem "pry", "0.11.3" do
        dep "coderay", "~> 1.1.0"
        dep "method_source", "~> 0.9.0"
      end

      gem "ffi", "1.9.23", "java"
      gem "ffi", "1.9.23"

      gem "extra", "1.0.0" do
        dep "ffi", ">= 0"
      end
    end

    dep "empyrean", "0.1.0"
    dep "pry"
    dep "extra"

    platforms "ruby", "java"

    should_resolve_as %w[coderay-1.1.2 empyrean-0.1.0 extra-1.0.0 ffi-1.9.23 ffi-1.9.23-java method_source-0.9.0 pry-0.11.3 pry-0.11.3-java spoon-0.0.6]
  end

  it "includes gems needed for at least one platform even when the platform specific requirement is processed earlier than the generic requirement" do
    @index = build_index do
      gem "empyrean", "0.1.0"
      gem "coderay", "1.1.2"
      gem "method_source", "0.9.0"

      gem "spoon", "0.0.6" do
        dep "ffi", ">= 0"
      end

      gem "pry", "0.11.3", "java" do
        dep "coderay", "~> 1.1.0"
        dep "method_source", "~> 0.9.0"
        dep "spoon", "~> 0.0"
      end

      gem "pry", "0.11.3" do
        dep "coderay", "~> 1.1.0"
        dep "method_source", "~> 0.9.0"
      end

      gem "ffi", "1.9.23", "java"
      gem "ffi", "1.9.23"

      gem "extra", "1.0.0" do
        dep "extra2", ">= 0"
      end

      gem "extra2", "1.0.0" do
        dep "extra3", ">= 0"
      end

      gem "extra3", "1.0.0" do
        dep "ffi", ">= 0"
      end
    end

    dep "empyrean", "0.1.0"
    dep "pry"
    dep "extra"

    platforms "ruby", "java"

    should_resolve_as %w[coderay-1.1.2 empyrean-0.1.0 extra-1.0.0 extra2-1.0.0 extra3-1.0.0 ffi-1.9.23 ffi-1.9.23-java method_source-0.9.0 pry-0.11.3 pry-0.11.3-java spoon-0.0.6]
  end

  it "properly adds platforms when platform requirements come from different dependencies" do
    @index = build_index do
      gem "ffi", "1.9.14"
      gem "ffi", "1.9.14", "universal-mingw32"

      gem "gssapi", "0.1"
      gem "gssapi", "0.2"
      gem "gssapi", "0.3"
      gem "gssapi", "1.2.0" do
        dep "ffi", ">= 1.0.1"
      end

      gem "mixlib-shellout", "2.2.6"
      gem "mixlib-shellout", "2.2.6", "universal-mingw32" do
        dep "win32-process", "~> 0.8.2"
      end

      # we need all these versions to get the sorting the same as it would be
      # pulling from rubygems.org
      %w[0.8.3 0.8.2 0.8.1 0.8.0].each do |v|
        gem "win32-process", v do
          dep "ffi", ">= 1.0.0"
        end
      end
    end

    dep "mixlib-shellout"
    dep "gssapi"

    platforms "universal-mingw32", "ruby"

    should_resolve_as %w[ffi-1.9.14 ffi-1.9.14-universal-mingw32 gssapi-1.2.0 mixlib-shellout-2.2.6 mixlib-shellout-2.2.6-universal-mingw32 win32-process-0.8.3]
  end

  describe "with mingw32" do
    before :each do
      @index = build_index do
        platforms "mingw32 mswin32 x64-mingw32 x64-mingw-ucrt" do |platform|
          gem "thin", "1.2.7", platform
        end
        gem "win32-api", "1.5.1", "universal-mingw32"
      end
    end

    it "finds mswin gems" do
      # win32 is hardcoded to get CPU x86 in rubygems
      platforms "mswin32"
      dep "thin"
      should_resolve_as %w[thin-1.2.7-x86-mswin32]
    end

    it "finds mingw gems" do
      # mingw is _not_ hardcoded to add CPU x86 in rubygems
      platforms "x86-mingw32"
      dep "thin"
      should_resolve_as %w[thin-1.2.7-mingw32]
    end

    it "finds x64-mingw32 gems" do
      platforms "x64-mingw32"
      dep "thin"
      should_resolve_as %w[thin-1.2.7-x64-mingw32]
    end

    it "finds universal-mingw gems on x86-mingw" do
      platform "x86-mingw32"
      dep "win32-api"
      should_resolve_as %w[win32-api-1.5.1-universal-mingw32]
    end

    it "finds universal-mingw gems on x64-mingw" do
      platform "x64-mingw32"
      dep "win32-api"
      should_resolve_as %w[win32-api-1.5.1-universal-mingw32]
    end

    if Gem.rubygems_version >= Gem::Version.new("3.2.28")
      it "finds x64-mingw-ucrt gems" do
        platforms "x64-mingw-ucrt"
        dep "thin"
        should_resolve_as %w[thin-1.2.7-x64-mingw-ucrt]
      end
    end

    if Gem.rubygems_version >= Gem::Version.new("3.3.18")
      it "finds universal-mingw gems on x64-mingw-ucrt" do
        platform "x64-mingw-ucrt"
        dep "win32-api"
        should_resolve_as %w[win32-api-1.5.1-universal-mingw32]
      end
    end
  end

  describe "with conflicting cases" do
    before :each do
      @index = build_index do
        gem "foo", "1.0.0" do
          dep "bar", ">= 0"
        end

        gem "bar", "1.0.0" do
          dep "baz", "~> 1.0.0"
        end

        gem "bar", "1.0.0", "java" do
          dep "baz", " ~> 1.1.0"
        end

        gem "baz", %w[1.0.0 1.1.0 1.2.0]
      end
    end

    it "takes the ruby version as fallback" do
      platforms "ruby", "java"
      dep "foo"

      should_resolve_as %w[bar-1.0.0 baz-1.0.0 foo-1.0.0]
    end
  end
end
