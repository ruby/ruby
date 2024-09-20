# frozen_string_literal: true

RSpec.describe "bundle install" do
  context "installing a gem fails" do
    it "prints out why that gem was being installed and the underlying error" do
      build_repo2 do
        build_gem "activesupport", "2.3.2" do |s|
          s.extensions << "Rakefile"
          s.write "Rakefile", <<-RUBY
            task :default do
              abort "make installing activesupport-2.3.2 fail"
            end
          RUBY
        end
      end

      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        gem "rails"
      G
      expect(err).to start_with("Gem::Ext::BuildError: ERROR: Failed to build gem native extension.")
      expect(err).to end_with(<<-M.strip)
An error occurred while installing activesupport (2.3.2), and Bundler cannot continue.

In Gemfile:
  rails was resolved to 2.3.2, which depends on
    actionmailer was resolved to 2.3.2, which depends on
      activesupport
                     M
    end

    context "because the downloaded .gem was invalid" do
      before do
        build_repo4 do
          build_gem "a"
        end

        gem_repo4("gems", "a-1.0.gem").open("w") {|f| f << "<html></html>" }
      end

      it "removes the downloaded .gem" do
        install_gemfile <<-G, raise_on_error: false
          source "https://gem.repo4"
          gem "a"
        G

        expect(default_bundle_path("cache", "a-1.0.gem")).not_to exist
      end
    end
  end
end
