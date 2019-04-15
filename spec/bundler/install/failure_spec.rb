# frozen_string_literal: true

RSpec.describe "bundle install" do
  context "installing a gem fails" do
    it "prints out why that gem was being installed" do
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

      install_gemfile <<-G
        source "file:\/\/localhost#{gem_repo2}"
        gem "rails"
      G
      expect(last_command.bundler_err).to end_with(normalize_uri_file(<<-M.strip))
An error occurred while installing activesupport (2.3.2), and Bundler cannot continue.
Make sure that `gem install activesupport -v '2.3.2' --source 'file://localhost#{gem_repo2}/'` succeeds before bundling.

In Gemfile:
  rails was resolved to 2.3.2, which depends on
    actionmailer was resolved to 2.3.2, which depends on
      activesupport
                     M
    end

    context "when installing a git gem" do
      it "does not tell the user to run 'gem install'" do
        build_git "activesupport", "2.3.2", :path => lib_path("activesupport") do |s|
          s.extensions << "Rakefile"
          s.write "Rakefile", <<-RUBY
            task :default do
              abort "make installing activesupport-2.3.2 fail"
            end
          RUBY
        end

        install_gemfile <<-G
          source "file:\/\/localhost#{gem_repo1}"
          gem "rails"
          gem "activesupport", :git => "#{lib_path("activesupport")}"
        G

        expect(last_command.bundler_err).to end_with(<<-M.strip)
An error occurred while installing activesupport (2.3.2), and Bundler cannot continue.

In Gemfile:
  rails was resolved to 2.3.2, which depends on
    actionmailer was resolved to 2.3.2, which depends on
      activesupport
                     M
      end
    end

    context "when installing a gem using a git block" do
      it "does not tell the user to run 'gem install'" do
        build_git "activesupport", "2.3.2", :path => lib_path("activesupport") do |s|
          s.extensions << "Rakefile"
          s.write "Rakefile", <<-RUBY
            task :default do
              abort "make installing activesupport-2.3.2 fail"
            end
          RUBY
        end

        install_gemfile <<-G
          source "file:\/\/localhost#{gem_repo1}"
          gem "rails"

          git "#{lib_path("activesupport")}" do
            gem "activesupport"
          end
        G

        expect(last_command.bundler_err).to end_with(<<-M.strip)
An error occurred while installing activesupport (2.3.2), and Bundler cannot continue.


In Gemfile:
  rails was resolved to 2.3.2, which depends on
    actionmailer was resolved to 2.3.2, which depends on
      activesupport
                     M
      end
    end

    it "prints out the hint for the remote source when available" do
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

      build_repo4 do
        build_gem "a"
      end

      install_gemfile <<-G
        source "file:\/\/localhost#{gem_repo4}"
        source "file:\/\/localhost#{gem_repo2}" do
          gem "rails"
        end
      G
      expect(last_command.bundler_err).to end_with(normalize_uri_file(<<-M.strip))
An error occurred while installing activesupport (2.3.2), and Bundler cannot continue.
Make sure that `gem install activesupport -v '2.3.2' --source 'file://localhost#{gem_repo2}/'` succeeds before bundling.

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
        install_gemfile <<-G
          source "file:#{gem_repo4}"
          gem "a"
        G

        expect(default_bundle_path("cache", "a-1.0.gem")).not_to exist
      end
    end
  end
end
