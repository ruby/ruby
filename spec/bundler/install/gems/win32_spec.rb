# frozen_string_literal: true

RSpec.describe "bundle install with win32-generated lockfile" do
  it "should read lockfile" do
    File.open(bundled_app_lock, "wb") do |f|
      f << "GEM\r\n"
      f << "  remote: #{file_uri_for(gem_repo1)}/\r\n"
      f << "  specs:\r\n"
      f << "\r\n"
      f << "    rack (1.0.0)\r\n"
      f << "\r\n"
      f << "PLATFORMS\r\n"
      f << "  ruby\r\n"
      f << "\r\n"
      f << "DEPENDENCIES\r\n"
      f << "  rack\r\n"
    end

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"

      gem "rack"
    G
  end
end
