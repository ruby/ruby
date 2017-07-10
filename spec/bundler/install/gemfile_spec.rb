# frozen_string_literal: true
require "spec_helper"

describe "bundle install" do
  context "with duplicated gems" do
    it "will display a warning" do
      install_gemfile <<-G
        gem 'rails', '~> 4.0.0'
        gem 'rails', '~> 4.0.0'
      G
      expect(out).to include("more than once")
    end
  end

  context "with --gemfile" do
    it "finds the gemfile" do
      gemfile bundled_app("NotGemfile"), <<-G
        source "file://#{gem_repo1}"
        gem 'rack'
      G

      bundle :install, :gemfile => bundled_app("NotGemfile")

      ENV["BUNDLE_GEMFILE"] = "NotGemfile"
      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end

  context "with gemfile set via config" do
    before do
      gemfile bundled_app("NotGemfile"), <<-G
        source "file://#{gem_repo1}"
        gem 'rack'
      G

      bundle "config --local gemfile #{bundled_app("NotGemfile")}"
    end
    it "uses the gemfile to install" do
      bundle "install"
      bundle "show"

      expect(out).to include("rack (1.0.0)")
    end
    it "uses the gemfile while in a subdirectory" do
      bundled_app("subdir").mkpath
      Dir.chdir(bundled_app("subdir")) do
        bundle "install"
        bundle "show"

        expect(out).to include("rack (1.0.0)")
      end
    end
  end

  context "with deprecated features" do
    before :each do
      in_app_root
    end

    it "reports that lib is an invalid option" do
      gemfile <<-G
        gem "rack", :lib => "rack"
      G

      bundle :install
      expect(out).to match(/You passed :lib as an option for gem 'rack', but it is invalid/)
    end
  end

  context "with engine specified in symbol" do
    it "does not raise any error parsing Gemfile" do
      simulate_ruby_version "2.3.0" do
        simulate_ruby_engine "jruby", "9.1.2.0" do
          install_gemfile! <<-G
            source "file://#{gem_repo1}"
            ruby "2.3.0", :engine => :jruby, :engine_version => "9.1.2.0"
          G

          expect(out).to match(/Bundle complete!/)
        end
      end
    end

    it "installation succeeds" do
      simulate_ruby_version "2.3.0" do
        simulate_ruby_engine "jruby", "9.1.2.0" do
          install_gemfile! <<-G
            source "file://#{gem_repo1}"
            ruby "2.3.0", :engine => :jruby, :engine_version => "9.1.2.0"
            gem "rack"
          G

          expect(the_bundle).to include_gems "rack 1.0.0"
        end
      end
    end
  end
end
