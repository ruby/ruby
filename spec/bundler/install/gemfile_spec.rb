# frozen_string_literal: true

RSpec.describe "bundle install" do
  context "with duplicated gems" do
    it "will display a warning" do
      install_gemfile <<-G, :raise_on_error => false
        source "#{file_uri_for(gem_repo1)}"

        gem 'rails', '~> 4.0.0'
        gem 'rails', '~> 4.0.0'
      G
      expect(err).to include("more than once")
    end
  end

  context "with --gemfile" do
    it "finds the gemfile" do
      gemfile bundled_app("NotGemfile"), <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G

      bundle :install, :gemfile => bundled_app("NotGemfile")

      # Specify BUNDLE_GEMFILE for `the_bundle`
      # to retrieve the proper Gemfile
      ENV["BUNDLE_GEMFILE"] = "NotGemfile"
      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end

  context "with gemfile set via config" do
    before do
      gemfile bundled_app("NotGemfile"), <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G

      bundle "config set --local gemfile #{bundled_app("NotGemfile")}"
    end
    it "uses the gemfile to install" do
      bundle "install"
      bundle "list"

      expect(out).to include("rack (1.0.0)")
    end
    it "uses the gemfile while in a subdirectory" do
      bundled_app("subdir").mkpath
      bundle "install", :dir => bundled_app("subdir")
      bundle "list", :dir => bundled_app("subdir")

      expect(out).to include("rack (1.0.0)")
    end
  end

  context "with deprecated features" do
    it "reports that lib is an invalid option" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "rack", :lib => "rack"
      G

      bundle :install, :raise_on_error => false
      expect(err).to match(/You passed :lib as an option for gem 'rack', but it is invalid/)
    end
  end

  context "with engine specified in symbol", :jruby do
    it "does not raise any error parsing Gemfile" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        ruby "#{RUBY_VERSION}", :engine => :jruby, :engine_version => "#{RUBY_ENGINE_VERSION}"
      G

      expect(out).to match(/Bundle complete!/)
    end

    it "installation succeeds" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        ruby "#{RUBY_VERSION}", :engine => :jruby, :engine_version => "#{RUBY_ENGINE_VERSION}"
        gem "rack"
      G

      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end

  context "with a Gemfile containing non-US-ASCII characters" do
    it "reads the Gemfile with the UTF-8 encoding by default" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

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
        source "#{file_uri_for(gem_repo1)}"

        str = "Il #{"\xE9".dup.force_encoding("binary")}tait une fois ..."
        puts "The source encoding is: " + str.encoding.name
      G

      expect(out).to include("The source encoding is: ISO-8859-1")
      expect(out).to include("Bundle complete!")
    end
  end
end
