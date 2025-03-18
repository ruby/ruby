# frozen_string_literal: true

RSpec.describe "bundle install" do
  context "with duplicated gems" do
    it "will display a warning" do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo1"

        gem 'rails', '~> 4.0.0'
        gem 'rails', '~> 4.0.0'
      G
      expect(err).to include("more than once")
    end
  end

  context "with --gemfile" do
    it "finds the gemfile" do
      gemfile bundled_app("NotGemfile"), <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G

      bundle :install, gemfile: bundled_app("NotGemfile")

      # Specify BUNDLE_GEMFILE for `the_bundle`
      # to retrieve the proper Gemfile
      ENV["BUNDLE_GEMFILE"] = "NotGemfile"
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end
  end

  context "with gemfile set via config" do
    before do
      gemfile bundled_app("NotGemfile"), <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G

      bundle "config set --local gemfile #{bundled_app("NotGemfile")}"
    end
    it "uses the gemfile to install" do
      bundle "install"
      bundle "list"

      expect(out).to include("myrack (1.0.0)")
    end
    it "uses the gemfile while in a subdirectory" do
      bundled_app("subdir").mkpath
      bundle "install", dir: bundled_app("subdir")
      bundle "list", dir: bundled_app("subdir")

      expect(out).to include("myrack (1.0.0)")
    end
  end

  it "reports that lib is an invalid option" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", :lib => "myrack"
    G

    bundle :install, raise_on_error: false
    expect(err).to match(/You passed :lib as an option for gem 'myrack', but it is invalid/)
  end

  it "reports that type is an invalid option" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", :type => "development"
    G

    bundle :install, raise_on_error: false
    expect(err).to match(/You passed :type as an option for gem 'myrack', but it is invalid/)
  end

  it "reports that gemfile is an invalid option" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", :gemfile => "foo"
    G

    bundle :install, raise_on_error: false
    expect(err).to match(/You passed :gemfile as an option for gem 'myrack', but it is invalid/)
  end

  context "when an internal error happens" do
    let(:bundler_bug) do
      create_file("bundler_bug.rb", <<~RUBY)
        require "bundler"

        module Bundler
          class Dsl
            def source(source, *args, &blk)
              nil.name
            end
          end
        end
      RUBY

      bundled_app("bundler_bug.rb").to_s
    end

    it "shows culprit file and line" do
      skip "ruby-core test setup has always \"lib\" in $LOAD_PATH so `require \"bundler\"` always activates the local version rather than using RubyGems gem activation stuff, causing conflicts" if ruby_core?

      install_gemfile "source 'https://gem.repo1'", requires: [bundler_bug], artifice: nil, raise_on_error: false
      expect(err).to include("bundler_bug.rb:6")
    end
  end

  context "with engine specified in symbol", :jruby_only do
    it "does not raise any error parsing Gemfile" do
      install_gemfile <<-G
        source "https://gem.repo1"
        ruby "#{RUBY_VERSION}", :engine => :jruby, :engine_version => "#{RUBY_ENGINE_VERSION}"
      G

      expect(out).to match(/Bundle complete!/)
    end

    it "installation succeeds" do
      install_gemfile <<-G
        source "https://gem.repo1"
        ruby "#{RUBY_VERSION}", :engine => :jruby, :engine_version => "#{RUBY_ENGINE_VERSION}"
        gem "myrack"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0"
    end
  end

  context "with a Gemfile containing non-US-ASCII characters" do
    it "reads the Gemfile with the UTF-8 encoding by default" do
      install_gemfile <<-G
        source "https://gem.repo1"

        str = "Il était une fois ..."
        puts "The source encoding is: " + str.encoding.name
      G

      expect(out).to include("The source encoding is: UTF-8")
      expect(out).not_to include("The source encoding is: ASCII-8BIT")
      expect(out).to include("Bundle complete!")
    end

    it "respects the magic encoding comment" do
      # NOTE: This works thanks to #eval interpreting the magic encoding comment
      install_gemfile <<-G
        # encoding: iso-8859-1
        source "https://gem.repo1"

        str = "Il #{"\xE9".dup.force_encoding("binary")}tait une fois ..."
        puts "The source encoding is: " + str.encoding.name
      G

      expect(out).to include("The source encoding is: ISO-8859-1")
      expect(out).to include("Bundle complete!")
    end
  end
end
