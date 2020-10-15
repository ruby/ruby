# frozen_string_literal: true

RSpec.describe "bundle install" do
  context "with gem sources" do
    context "when gems include a fund URI" do
      it "displays the plural fund message after installing" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem 'has_metadata'
          gem 'has_funding'
          gem 'rack-obama'
        G

        expect(out).to include("2 installed gems you directly depend on are looking for funding.")
      end

      it "displays the singular fund message after installing" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem 'has_funding'
          gem 'rack-obama'
        G

        expect(out).to include("1 installed gem you directly depend on is looking for funding.")
      end
    end

    context "when gems do not include fund messages" do
      it "does not display any fund messages" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "activesupport"
        G

        expect(out).not_to include("gem you depend on")
      end
    end

    context "when a dependency includes a fund message" do
      it "does not display the fund message" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem 'gem_with_dependent_funding'
        G

        expect(out).not_to include("gem you depend on")
      end
    end
  end

  context "with git sources" do
    context "when gems include fund URI" do
      it "displays the fund message after installing" do
        build_git "also_has_funding" do |s|
          s.metadata = {
            "funding_uri" => "https://example.com/also_has_funding/funding",
          }
        end
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem 'also_has_funding', :git => '#{lib_path("also_has_funding-1.0")}'
        G

        expect(out).to include("1 installed gem you directly depend on is looking for funding.")
      end

      it "displays the fund message if repo is updated" do
        build_git "also_has_funding" do |s|
          s.metadata = {
            "funding_uri" => "https://example.com/also_has_funding/funding",
          }
        end
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem 'also_has_funding', :git => '#{lib_path("also_has_funding-1.0")}'
        G

        build_git "also_has_funding", "1.1" do |s|
          s.metadata = {
            "funding_uri" => "https://example.com/also_has_funding/funding",
          }
        end
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem 'also_has_funding', :git => '#{lib_path("also_has_funding-1.1")}'
        G

        expect(out).to include("1 installed gem you directly depend on is looking for funding.")
      end

      it "displays the fund message if repo is not updated" do
        build_git "also_has_funding" do |s|
          s.metadata = {
            "funding_uri" => "https://example.com/also_has_funding/funding",
          }
        end
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem 'also_has_funding', :git => '#{lib_path("also_has_funding-1.0")}'
        G

        bundle :install
        expect(out).to include("1 installed gem you directly depend on is looking for funding.")

        bundle :install
        expect(out).to include("1 installed gem you directly depend on is looking for funding.")
      end
    end
  end
end
