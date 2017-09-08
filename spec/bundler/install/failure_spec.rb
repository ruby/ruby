# frozen_string_literal: true
require "spec_helper"

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
        source "file:#{gem_repo2}"
        gem "rails"
      G
      expect(out).to end_with(<<-M.strip)
An error occurred while installing activesupport (2.3.2), and Bundler cannot continue.
Make sure that `gem install activesupport -v '2.3.2'` succeeds before bundling.

In Gemfile:
  rails was resolved to 2.3.2, which depends on
    actionmailer was resolved to 2.3.2, which depends on
      activesupport
                     M
    end
  end
end
