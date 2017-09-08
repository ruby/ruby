# frozen_string_literal: true
require "spec_helper"

RSpec.describe "path sources" do
  describe "bundle update --source" do
    it "shows the previous version of the gem when updated from path source" do
      build_lib "activesupport", "2.3.5", :path => lib_path("rails/activesupport")

      install_gemfile <<-G
      gem "activesupport", :path => "#{lib_path("rails/activesupport")}"
      G

      build_lib "activesupport", "3.0", :path => lib_path("rails/activesupport")

      bundle "update --source activesupport"
      expect(out).to include("Using activesupport 3.0 (was 2.3.5) from source at `#{lib_path("rails/activesupport")}`")
    end
  end
end
