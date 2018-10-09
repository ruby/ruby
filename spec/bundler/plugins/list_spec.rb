# frozen_string_literal: true

RSpec.describe "bundler plugin list" do
  before do
    build_repo2 do
      build_plugin "foo" do |s|
        s.write "plugins.rb", <<-RUBY
          class Foo < Bundler::Plugin::API
            command "shout"

            def exec(command, args)
              puts "Foo shout"
            end
          end
        RUBY
      end
      build_plugin "bar" do |s|
        s.write "plugins.rb", <<-RUBY
          class Bar < Bundler::Plugin::API
            command "scream"

            def exec(command, args)
              puts "Bar scream"
            end
          end
        RUBY
      end
    end
  end

  context "no plugins installed" do
    it "shows proper no plugins installed message" do
      bundle "plugin list"

      expect(out).to include("No plugins installed")
    end
  end

  context "single plugin installed" do
    it "shows plugin name with commands list" do
      bundle "plugin install foo --source file://#{gem_repo2}"
      plugin_should_be_installed("foo")
      bundle "plugin list"

      expected_output = "foo\n-----\n  shout"
      expect(out).to include(expected_output)
    end
  end

  context "multiple plugins installed" do
    it "shows plugin names with commands list" do
      bundle "plugin install foo bar --source file://#{gem_repo2}"
      plugin_should_be_installed("foo", "bar")
      bundle "plugin list"

      if RUBY_VERSION < "1.9"
        # Bundler::Plugin::Index#installed_plugins is keys of Hash,
        # and Hash is not ordered in prior to Ruby 1.9.
        # So, foo and bar plugins are not always listed in that order.
        expected_output1 = "foo\n-----\n  shout"
        expect(out).to include(expected_output1)
        expected_output2 = "bar\n-----\n  scream"
        expect(out).to include(expected_output2)
      else
        expected_output = "foo\n-----\n  shout\n\nbar\n-----\n  scream"
        expect(out).to include(expected_output)
      end
    end
  end
end
