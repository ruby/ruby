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

  describe "with mingw32" do
    before :each do
      @index = build_index do
        platforms "mingw32 mswin32 x64-mingw32" do |platform|
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

    it "finds x64-mingw gems" do
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

    it "reports on the conflict" do
      platforms "ruby", "java"
      dep "foo"

      should_conflict_on "baz"
    end
  end
end
