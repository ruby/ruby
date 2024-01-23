# frozen_string_literal: true

RSpec.describe ".bundle/config" do
  describe "config" do
    before { bundle "config set foo bar" }

    it "prints a detailed report of local and user configuration" do
      bundle "config list"

      expect(out).to include("Settings are listed in order of priority. The top value will be used")
      expect(out).to include("foo\nSet for the current user")
      expect(out).to include(": \"bar\"")
    end

    context "given --parseable flag" do
      it "prints a minimal report of local and user configuration" do
        bundle "config list --parseable"
        expect(out).to include("foo=bar")
      end

      context "with global config" do
        it "prints config assigned to local scope" do
          bundle "config set --local foo bar2"
          bundle "config list --parseable"
          expect(out).to include("foo=bar2")
        end
      end

      context "with env overwrite" do
        it "prints config with env" do
          bundle "config list --parseable", env: { "BUNDLE_FOO" => "bar3" }
          expect(out).to include("foo=bar3")
        end
      end
    end
  end

  describe "location with a gemfile" do
    before :each do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", "1.0.0"
      G
    end

    it "is local by default" do
      bundle "config set foo bar"
      expect(bundled_app(".bundle/config")).to exist
      expect(home(".bundle/config")).not_to exist
    end

    it "can be moved with an environment variable" do
      ENV["BUNDLE_APP_CONFIG"] = tmp("foo/bar").to_s
      bundle "config set --local path vendor/bundle"
      bundle "install"

      expect(bundled_app(".bundle")).not_to exist
      expect(tmp("foo/bar/config")).to exist
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "can provide a relative path with the environment variable" do
      FileUtils.mkdir_p bundled_app("omg")

      ENV["BUNDLE_APP_CONFIG"] = "../foo"
      bundle "config set --local path vendor/bundle"
      bundle "install", dir: bundled_app("omg")

      expect(bundled_app(".bundle")).not_to exist
      expect(bundled_app("../foo/config")).to exist
      expect(the_bundle).to include_gems "rack 1.0.0", dir: bundled_app("omg")
    end
  end

  describe "location without a gemfile" do
    it "is global by default" do
      bundle "config set foo bar"
      expect(bundled_app(".bundle/config")).not_to exist
      expect(home(".bundle/config")).to exist
    end

    it "works with an absolute path" do
      ENV["BUNDLE_APP_CONFIG"] = tmp("foo/bar").to_s
      bundle "config set --local path vendor/bundle"

      expect(bundled_app(".bundle")).not_to exist
      expect(tmp("foo/bar/config")).to exist
    end
  end

  describe "config location" do
    let(:bundle_user_config) { File.join(Dir.home, ".config/bundler") }

    before do
      Dir.mkdir File.dirname(bundle_user_config)
    end

    it "can be configured through BUNDLE_USER_CONFIG" do
      bundle "config set path vendor", env: { "BUNDLE_USER_CONFIG" => bundle_user_config }
      bundle "config get path", env: { "BUNDLE_USER_CONFIG" => bundle_user_config }
      expect(out).to include("Set for the current user (#{bundle_user_config}): \"vendor\"")
    end

    context "when not explicitly configured, but BUNDLE_USER_HOME set" do
      let(:bundle_user_home) { bundled_app(".bundle").to_s }

      it "uses the right location" do
        bundle "config set path vendor", env: { "BUNDLE_USER_HOME" => bundle_user_home }
        bundle "config get path", env: { "BUNDLE_USER_HOME" => bundle_user_home }
        expect(out).to include("Set for the current user (#{bundle_user_home}/config): \"vendor\"")
      end
    end
  end

  describe "global" do
    before(:each) do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", "1.0.0"
      G
    end

    it "is the default" do
      bundle "config set foo global"
      run "puts Bundler.settings[:foo]"
      expect(out).to eq("global")
    end

    it "can also be set explicitly" do
      bundle "config set --global foo global"
      run "puts Bundler.settings[:foo]"
      expect(out).to eq("global")
    end

    it "has lower precedence than local" do
      bundle "config set --local  foo local"

      bundle "config set --global foo global"
      expect(out).to match(/Your application has set foo to "local"/)

      run "puts Bundler.settings[:foo]"
      expect(out).to eq("local")
    end

    it "has lower precedence than env" do
      ENV["BUNDLE_FOO"] = "env"

      bundle "config set --global foo global"
      expect(out).to match(/You have a bundler environment variable for foo set to "env"/)

      run "puts Bundler.settings[:foo]"
      expect(out).to eq("env")
    ensure
      ENV.delete("BUNDLE_FOO")
    end

    it "can be deleted" do
      bundle "config set --global foo global"
      bundle "config unset foo"

      run "puts Bundler.settings[:foo] == nil"
      expect(out).to eq("true")
    end

    it "warns when overriding" do
      bundle "config set --global foo previous"
      bundle "config set --global foo global"
      expect(out).to match(/You are replacing the current global value of foo/)

      run "puts Bundler.settings[:foo]"
      expect(out).to eq("global")
    end

    it "does not warn when using the same value twice" do
      bundle "config set --global foo value"
      bundle "config set --global foo value"
      expect(out).not_to match(/You are replacing the current global value of foo/)

      run "puts Bundler.settings[:foo]"
      expect(out).to eq("value")
    end

    it "expands the path at time of setting" do
      bundle "config set --global local.foo .."
      run "puts Bundler.settings['local.foo']"
      expect(out).to eq(File.expand_path(bundled_app.to_s + "/.."))
    end

    it "saves with parseable option" do
      bundle "config set --global --parseable foo value"
      expect(out).to eq("foo=value")
      run "puts Bundler.settings['foo']"
      expect(out).to eq("value")
    end

    context "when replacing a current value with the parseable flag" do
      before { bundle "config set --global foo value" }
      it "prints the current value in a parseable format" do
        bundle "config set --global --parseable foo value2"
        expect(out).to eq "foo=value2"
        run "puts Bundler.settings['foo']"
        expect(out).to eq("value2")
      end
    end
  end

  describe "local" do
    before(:each) do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", "1.0.0"
      G
    end

    it "can also be set explicitly" do
      bundle "config set --local foo local"
      run "puts Bundler.settings[:foo]"
      expect(out).to eq("local")
    end

    it "has higher precedence than env" do
      ENV["BUNDLE_FOO"] = "env"
      bundle "config set --local foo local"

      run "puts Bundler.settings[:foo]"
      expect(out).to eq("local")
    ensure
      ENV.delete("BUNDLE_FOO")
    end

    it "can be deleted" do
      bundle "config set --local foo local"
      bundle "config unset foo"

      run "puts Bundler.settings[:foo] == nil"
      expect(out).to eq("true")
    end

    it "warns when overriding" do
      bundle "config set --local foo previous"
      bundle "config set --local foo local"
      expect(out).to match(/You are replacing the current local value of foo/)

      run "puts Bundler.settings[:foo]"
      expect(out).to eq("local")
    end

    it "expands the path at time of setting" do
      bundle "config set --local local.foo .."
      run "puts Bundler.settings['local.foo']"
      expect(out).to eq(File.expand_path(bundled_app.to_s + "/.."))
    end

    it "can be deleted with parseable option" do
      bundle "config set --local foo value"
      bundle "config unset --parseable foo"
      expect(out).to eq ""
      run "puts Bundler.settings['foo'] == nil"
      expect(out).to eq("true")
    end
  end

  describe "env" do
    before(:each) do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", "1.0.0"
      G
    end

    it "can set boolean properties via the environment" do
      ENV["BUNDLE_FROZEN"] = "true"

      run "if Bundler.settings[:frozen]; puts 'true' else puts 'false' end"
      expect(out).to eq("true")
    end

    it "can set negative boolean properties via the environment" do
      run "if Bundler.settings[:frozen]; puts 'true' else puts 'false' end"
      expect(out).to eq("false")

      ENV["BUNDLE_FROZEN"] = "false"

      run "if Bundler.settings[:frozen]; puts 'true' else puts 'false' end"
      expect(out).to eq("false")

      ENV["BUNDLE_FROZEN"] = "0"

      run "if Bundler.settings[:frozen]; puts 'true' else puts 'false' end"
      expect(out).to eq("false")

      ENV["BUNDLE_FROZEN"] = ""

      run "if Bundler.settings[:frozen]; puts 'true' else puts 'false' end"
      expect(out).to eq("false")
    end

    it "can set properties with periods via the environment" do
      ENV["BUNDLE_FOO__BAR"] = "baz"

      run "puts Bundler.settings['foo.bar']"
      expect(out).to eq("baz")
    end
  end

  describe "parseable option" do
    it "prints an empty string" do
      bundle "config get foo --parseable"

      expect(out).to eq ""
    end

    it "only prints the value of the config" do
      bundle "config set foo local"
      bundle "config get foo --parseable"

      expect(out).to eq "foo=local"
    end

    it "can print global config" do
      bundle "config set --global bar value"
      bundle "config get bar --parseable"

      expect(out).to eq "bar=value"
    end

    it "prefers local config over global" do
      bundle "config set --local bar value2"
      bundle "config set --global bar value"
      bundle "config get bar --parseable"

      expect(out).to eq "bar=value2"
    end
  end

  describe "gem mirrors" do
    before(:each) do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", "1.0.0"
      G
    end

    it "configures mirrors using keys with `mirror.`" do
      bundle "config set --local mirror.http://gems.example.org http://gem-mirror.example.org"
      run(<<-E)
Bundler.settings.gem_mirrors.each do |k, v|
  puts "\#{k} => \#{v}"
end
E
      expect(out).to eq("http://gems.example.org/ => http://gem-mirror.example.org/")
    end
  end

  describe "quoting" do
    before(:each) { gemfile "source \"#{file_uri_for(gem_repo1)}\"" }
    let(:long_string) do
      "--with-xml2-include=/usr/pkg/include/libxml2 --with-xml2-lib=/usr/pkg/lib " \
      "--with-xslt-dir=/usr/pkg"
    end

    it "saves quotes" do
      bundle "config set foo something\\'"
      run "puts Bundler.settings[:foo]"
      expect(out).to eq("something'")
    end

    it "doesn't return quotes around values" do
      bundle "config set foo '1'"
      run "puts Bundler.settings.send(:local_config_file).read"
      expect(out).to include('"1"')
      run "puts Bundler.settings[:foo]"
      expect(out).to eq("1")
    end

    it "doesn't duplicate quotes around values" do
      bundled_app(".bundle").mkpath
      File.open(bundled_app(".bundle/config"), "w") do |f|
        f.write 'BUNDLE_FOO: "$BUILD_DIR"'
      end

      bundle "config set bar baz"
      run "puts Bundler.settings.send(:local_config_file).read"

      # Starting in Ruby 2.1, YAML automatically adds double quotes
      # around some values, including $ and newlines.
      expect(out).to include('BUNDLE_FOO: "$BUILD_DIR"')
    end

    it "doesn't duplicate quotes around long wrapped values" do
      bundle "config set foo #{long_string}"

      run "puts Bundler.settings[:foo]"
      expect(out).to eq(long_string)

      bundle "config set bar baz"

      run "puts Bundler.settings[:foo]"
      expect(out).to eq(long_string)
    end
  end

  describe "very long lines" do
    before(:each) do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", "1.0.0"
      G
    end

    let(:long_string) do
      "--with-xml2-include=/usr/pkg/include/libxml2 --with-xml2-lib=/usr/pkg/lib " \
      "--with-xslt-dir=/usr/pkg"
    end

    let(:long_string_without_special_characters) do
      "here is quite a long string that will wrap to a second line but will not be " \
      "surrounded by quotes"
    end

    it "doesn't wrap values" do
      bundle "config set foo #{long_string}"
      run "puts Bundler.settings[:foo]"
      expect(out).to match(long_string)
    end

    it "can read wrapped unquoted values" do
      bundle "config set foo #{long_string_without_special_characters}"
      run "puts Bundler.settings[:foo]"
      expect(out).to match(long_string_without_special_characters)
    end
  end

  describe "commented out settings with urls" do
    before do
      bundle "config set #mirror.https://rails-assets.org http://localhost:9292"
    end

    it "does not make bundler crash and ignores the configuration" do
      bundle "config list --parseable"

      expect(out).to eq("#mirror.https://rails-assets.org/=http://localhost:9292")
      expect(err).to be_empty

      ruby(<<~RUBY)
        require "bundler"
        print Bundler.settings.mirror_for("https://rails-assets.org")
      RUBY
      expect(out).to eq("https://rails-assets.org/")
      expect(err).to be_empty

      bundle "config set mirror.all http://localhost:9293"
      ruby(<<~RUBY)
        require "bundler"
        print Bundler.settings.mirror_for("https://rails-assets.org")
      RUBY
      expect(out).to eq("http://localhost:9293/")
      expect(err).to be_empty
    end
  end

  describe "subcommands" do
    it "list" do
      bundle "config list", env: { "BUNDLE_FOO" => "bar" }
      expect(out).to eq "Settings are listed in order of priority. The top value will be used.\nfoo\nSet via BUNDLE_FOO: \"bar\""

      bundle "config list", env: { "BUNDLE_FOO" => "bar" }, parseable: true
      expect(out).to eq "foo=bar"
    end

    it "list with credentials" do
      bundle "config list", env: { "BUNDLE_GEMS__MYSERVER__COM" => "user:password" }
      expect(out).to eq "Settings are listed in order of priority. The top value will be used.\ngems.myserver.com\nSet via BUNDLE_GEMS__MYSERVER__COM: \"user:[REDACTED]\""

      bundle "config list", parseable: true, env: { "BUNDLE_GEMS__MYSERVER__COM" => "user:password" }
      expect(out).to eq "gems.myserver.com=user:password"
    end

    it "list with API token credentials" do
      bundle "config list", env: { "BUNDLE_GEMS__MYSERVER__COM" => "api_token:x-oauth-basic" }
      expect(out).to eq "Settings are listed in order of priority. The top value will be used.\ngems.myserver.com\nSet via BUNDLE_GEMS__MYSERVER__COM: \"[REDACTED]:x-oauth-basic\""

      bundle "config list", parseable: true, env: { "BUNDLE_GEMS__MYSERVER__COM" => "api_token:x-oauth-basic" }
      expect(out).to eq "gems.myserver.com=api_token:x-oauth-basic"
    end

    it "get" do
      ENV["BUNDLE_BAR"] = "bar_val"

      bundle "config get foo"
      expect(out).to eq "Settings for `foo` in order of priority. The top value will be used\nYou have not configured a value for `foo`"

      ENV["BUNDLE_FOO"] = "foo_val"

      bundle "config get foo --parseable"
      expect(out).to eq "foo=foo_val"

      bundle "config get foo"
      expect(out).to eq "Settings for `foo` in order of priority. The top value will be used\nSet via BUNDLE_FOO: \"foo_val\""
    end

    it "set" do
      bundle "config set foo 1"
      expect(out).to eq ""

      bundle "config set --local foo 2"
      expect(out).to eq ""

      bundle "config set --global foo 3"
      expect(out).to eq "Your application has set foo to \"2\". This will override the global value you are currently setting"

      bundle "config set --parseable --local foo 4"
      expect(out).to eq "foo=4"

      bundle "config set --local foo 4.1"
      expect(out).to eq "You are replacing the current local value of foo, which is currently \"4\""

      bundle "config set --global --local foo 5", raise_on_error: false
      expect(last_command).to be_failure
      expect(err).to eq "The options global and local were specified. Please only use one of the switches at a time."
    end

    it "unset" do
      bundle "config unset foo"
      expect(out).to eq ""

      bundle "config set foo 1"
      bundle "config unset foo --parseable"
      expect(out).to eq ""

      bundle "config set --local foo 1"
      bundle "config set --global foo 2"

      bundle "config unset foo"
      expect(out).to eq ""
      expect(bundle("config get foo")).to eq "Settings for `foo` in order of priority. The top value will be used\nYou have not configured a value for `foo`"

      bundle "config set --local foo 1"
      bundle "config set --global foo 2"

      bundle "config unset foo --local"
      expect(out).to eq ""
      expect(bundle("config get foo")).to eq "Settings for `foo` in order of priority. The top value will be used\nSet for the current user (#{home(".bundle/config")}): \"2\""
      bundle "config unset foo --global"
      expect(out).to eq ""
      expect(bundle("config get foo")).to eq "Settings for `foo` in order of priority. The top value will be used\nYou have not configured a value for `foo`"

      bundle "config set --local foo 1"
      bundle "config set --global foo 2"

      bundle "config unset foo --global"
      expect(out).to eq ""
      expect(bundle("config get foo")).to eq "Settings for `foo` in order of priority. The top value will be used\nSet for your local app (#{bundled_app(".bundle/config")}): \"1\""
      bundle "config unset foo --local"
      expect(out).to eq ""
      expect(bundle("config get foo")).to eq "Settings for `foo` in order of priority. The top value will be used\nYou have not configured a value for `foo`"

      bundle "config unset foo --local --global", raise_on_error: false
      expect(last_command).to be_failure
      expect(err).to eq "The options global and local were specified. Please only use one of the switches at a time."
    end
  end
end

RSpec.describe "setting gemfile via config" do
  context "when only the non-default Gemfile exists" do
    it "persists the gemfile location to .bundle/config" do
      gemfile bundled_app("NotGemfile"), <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G

      bundle "config set --local gemfile #{bundled_app("NotGemfile")}"
      expect(File.exist?(bundled_app(".bundle/config"))).to eq(true)

      bundle "config list"
      expect(out).to include("NotGemfile")
    end
  end
end
