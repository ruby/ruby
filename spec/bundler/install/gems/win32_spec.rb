# frozen_string_literal: true

RSpec.describe "bundle install with win32-generated lockfile" do
  it "should read lockfile" do
    File.open(bundled_app_lock, "wb") do |f|
      f << "GEM\r\n"
      f << "  remote: https://gem.repo1/\r\n"
      f << "  specs:\r\n"
      f << "\r\n"
      f << "    myrack (1.0.0)\r\n"
      f << "\r\n"
      f << "PLATFORMS\r\n"
      f << "  ruby\r\n"
      f << "\r\n"
      f << "DEPENDENCIES\r\n"
      f << "  myrack\r\n"
    end

    install_gemfile <<-G
      source "https://gem.repo1"

      gem "myrack"
    G
  end
end
