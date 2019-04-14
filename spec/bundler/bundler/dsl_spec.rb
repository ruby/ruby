# frozen_string_literal: true

RSpec.describe Bundler::Dsl do
  before do
    @rubygems = double("rubygems")
    allow(Bundler::Source::Rubygems).to receive(:new) { @rubygems }
  end

  describe "#git_source" do
    it "registers custom hosts" do
      subject.git_source(:example) {|repo_name| "git@git.example.com:#{repo_name}.git" }
      subject.git_source(:foobar) {|repo_name| "git@foobar.com:#{repo_name}.git" }
      subject.gem("dobry-pies", :example => "strzalek/dobry-pies")
      example_uri = "git@git.example.com:strzalek/dobry-pies.git"
      expect(subject.dependencies.first.source.uri).to eq(example_uri)
    end

    it "raises exception on invalid hostname" do
      expect do
        subject.git_source(:group) {|repo_name| "git@git.example.com:#{repo_name}.git" }
      end.to raise_error(Bundler::InvalidOption)
    end

    it "expects block passed" do
      expect { subject.git_source(:example) }.to raise_error(Bundler::InvalidOption)
    end

    context "github_https feature flag" do
      it "is true when github.https is true" do
        bundle "config set github.https true"
        expect(Bundler.feature_flag.github_https?).to eq true
      end
    end

    shared_examples_for "the github DSL" do |protocol|
      context "when full repo is used" do
        let(:repo) { "indirect/sparks" }

        it "converts :github to URI using #{protocol}" do
          subject.gem("sparks", :github => repo)
          github_uri = "#{protocol}://github.com/#{repo}.git"
          expect(subject.dependencies.first.source.uri).to eq(github_uri)
        end
      end

      context "when shortcut repo is used" do
        let(:repo) { "rails" }

        it "converts :github to URI using #{protocol}" do
          subject.gem("sparks", :github => repo)
          github_uri = "#{protocol}://github.com/#{repo}/#{repo}.git"
          expect(subject.dependencies.first.source.uri).to eq(github_uri)
        end
      end
    end

    context "default hosts (git, gist)" do
      context "when github.https config is true" do
        before { bundle "config set github.https true" }

        it_behaves_like "the github DSL", "https"
      end

      context "when github.https config is false", :bundler => "2" do
        before { bundle "config set github.https false" }

        it_behaves_like "the github DSL", "git"
      end

      context "when github.https config is false", :bundler => "3" do
        before { bundle "config set github.https false" }

        pending "should show a proper message about the removed setting"
      end

      context "by default", :bundler => "2" do
        it_behaves_like "the github DSL", "https"
      end

      context "by default", :bundler => "3" do
        it_behaves_like "the github DSL", "https"
      end

      it "converts numeric :gist to :git" do
        subject.gem("not-really-a-gem", :gist => 2_859_988)
        github_uri = "https://gist.github.com/2859988.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "converts :gist to :git" do
        subject.gem("not-really-a-gem", :gist => "2859988")
        github_uri = "https://gist.github.com/2859988.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "converts :bitbucket to :git" do
        subject.gem("not-really-a-gem", :bitbucket => "mcorp/flatlab-rails")
        bitbucket_uri = "https://mcorp@bitbucket.org/mcorp/flatlab-rails.git"
        expect(subject.dependencies.first.source.uri).to eq(bitbucket_uri)
      end

      it "converts 'mcorp' to 'mcorp/mcorp'" do
        subject.gem("not-really-a-gem", :bitbucket => "mcorp")
        bitbucket_uri = "https://mcorp@bitbucket.org/mcorp/mcorp.git"
        expect(subject.dependencies.first.source.uri).to eq(bitbucket_uri)
      end
    end

    context "default git sources", :bundler => "4" do
      it "has none" do
        expect(subject.instance_variable_get(:@git_sources)).to eq({})
      end
    end
  end

  describe "#method_missing" do
    it "raises an error for unknown DSL methods" do
      expect(Bundler).to receive(:read_file).with(bundled_app("Gemfile").to_s).
        and_return("unknown")

      error_msg = "There was an error parsing `Gemfile`: Undefined local variable or method `unknown' for Gemfile. Bundler cannot continue."
      expect { subject.eval_gemfile("Gemfile") }.
        to raise_error(Bundler::GemfileError, Regexp.new(error_msg))
    end
  end

  describe "#eval_gemfile" do
    it "handles syntax errors with a useful message" do
      expect(Bundler).to receive(:read_file).with(bundled_app("Gemfile").to_s).and_return("}")
      expect { subject.eval_gemfile("Gemfile") }.
        to raise_error(Bundler::GemfileError, /There was an error parsing `Gemfile`: (syntax error, unexpected tSTRING_DEND|(compile error - )?syntax error, unexpected '\}'). Bundler cannot continue./)
    end

    it "distinguishes syntax errors from evaluation errors" do
      expect(Bundler).to receive(:read_file).with(bundled_app("Gemfile").to_s).and_return(
        "ruby '2.1.5', :engine => 'ruby', :engine_version => '1.2.4'"
      )
      expect { subject.eval_gemfile("Gemfile") }.
        to raise_error(Bundler::GemfileError, /There was an error evaluating `Gemfile`: ruby_version must match the :engine_version for MRI/)
    end
  end

  describe "#gem" do
    [:ruby, :ruby_18, :ruby_19, :ruby_20, :ruby_21, :ruby_22, :ruby_23, :ruby_24, :ruby_25, :mri, :mri_18, :mri_19,
     :mri_20, :mri_21, :mri_22, :mri_23, :mri_24, :mri_25, :jruby, :rbx, :truffleruby].each do |platform|
      it "allows #{platform} as a valid platform" do
        subject.gem("foo", :platform => platform)
      end
    end

    it "rejects invalid platforms" do
      expect { subject.gem("foo", :platform => :bogus) }.
        to raise_error(Bundler::GemfileError, /is not a valid platform/)
    end

    it "rejects empty gem name" do
      expect { subject.gem("") }.
        to raise_error(Bundler::GemfileError, /an empty gem name is not valid/)
    end

    it "rejects with a leading space in the name" do
      expect { subject.gem(" foo") }.
        to raise_error(Bundler::GemfileError, /' foo' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a trailing space in the name" do
      expect { subject.gem("foo ") }.
        to raise_error(Bundler::GemfileError, /'foo ' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a space in the gem name" do
      expect { subject.gem("fo o") }.
        to raise_error(Bundler::GemfileError, /'fo o' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a tab in the gem name" do
      expect { subject.gem("fo\to") }.
        to raise_error(Bundler::GemfileError, /'fo\to' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a newline in the gem name" do
      expect { subject.gem("fo\no") }.
        to raise_error(Bundler::GemfileError, /'fo\no' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a carriage return in the gem name" do
      expect { subject.gem("fo\ro") }.
        to raise_error(Bundler::GemfileError, /'fo\ro' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a form feed in the gem name" do
      expect { subject.gem("fo\fo") }.
        to raise_error(Bundler::GemfileError, /'fo\fo' is not a valid gem name because it contains whitespace/)
    end

    it "rejects symbols as gem name" do
      expect { subject.gem(:foo) }.
        to raise_error(Bundler::GemfileError, /You need to specify gem names as Strings. Use 'gem "foo"' instead/)
    end

    it "rejects branch option on non-git gems" do
      expect { subject.gem("foo", :branch => "test") }.
        to raise_error(Bundler::GemfileError, /The `branch` option for `gem 'foo'` is not allowed. Only gems with a git source can specify a branch/)
    end

    it "allows specifying a branch on git gems" do
      subject.gem("foo", :branch => "test", :git => "http://mytestrepo")
      dep = subject.dependencies.last
      expect(dep.name).to eq "foo"
    end

    it "allows specifying a branch on git gems with a git_source" do
      subject.git_source(:test_source) {|n| "https://github.com/#{n}" }
      subject.gem("foo", :branch => "test", :test_source => "bundler/bundler")
      dep = subject.dependencies.last
      expect(dep.name).to eq "foo"
    end
  end

  describe "#gemspec" do
    let(:spec) do
      Gem::Specification.new do |gem|
        gem.name = "example"
        gem.platform = platform
      end
    end

    before do
      allow(Dir).to receive(:[]).and_return(["spec_path"])
      allow(Bundler).to receive(:load_gemspec).with("spec_path").and_return(spec)
      allow(Bundler).to receive(:default_gemfile).and_return(Pathname.new("./Gemfile"))
    end

    context "with a ruby platform" do
      let(:platform) { "ruby" }

      it "keeps track of the ruby platforms in the dependency" do
        subject.gemspec
        expect(subject.dependencies.last.platforms).to eq(Bundler::Dependency::REVERSE_PLATFORM_MAP[Gem::Platform::RUBY])
      end
    end

    context "with a jruby platform" do
      let(:platform) { "java" }

      it "keeps track of the jruby platforms in the dependency" do
        allow(Gem::Platform).to receive(:local).and_return(java)
        subject.gemspec
        expect(subject.dependencies.last.platforms).to eq(Bundler::Dependency::REVERSE_PLATFORM_MAP[Gem::Platform::JAVA])
      end
    end
  end

  context "can bundle groups of gems with" do
    # git "https://github.com/rails/rails.git" do
    #   gem "railties"
    #   gem "action_pack"
    #   gem "active_model"
    # end
    describe "#git" do
      it "from a single repo" do
        rails_gems = %w[railties action_pack active_model]
        subject.git "https://github.com/rails/rails.git" do
          rails_gems.each {|rails_gem| subject.send :gem, rails_gem }
        end
        expect(subject.dependencies.map(&:name)).to match_array rails_gems
      end
    end

    # github 'spree' do
    #   gem 'spree_core'
    #   gem 'spree_api'
    #   gem 'spree_backend'
    # end
    describe "#github", :bundler => "< 3" do
      it "from github" do
        spree_gems = %w[spree_core spree_api spree_backend]
        subject.github "spree" do
          spree_gems.each {|spree_gem| subject.send :gem, spree_gem }
        end

        subject.dependencies.each do |d|
          expect(d.source.uri).to eq("https://github.com/spree/spree.git")
        end
      end
    end

    describe "#github", :bundler => "3" do
      it "from github" do
        spree_gems = %w[spree_core spree_api spree_backend]
        subject.github "spree" do
          spree_gems.each {|spree_gem| subject.send :gem, spree_gem }
        end

        subject.dependencies.each do |d|
          expect(d.source.uri).to eq("https://github.com/spree/spree.git")
        end
      end
    end

    describe "#github", :bundler => "3" do
      it "from github" do
        spree_gems = %w[spree_core spree_api spree_backend]
        subject.github "spree" do
          spree_gems.each {|spree_gem| subject.send :gem, spree_gem }
        end

        subject.dependencies.each do |d|
          expect(d.source.uri).to eq("https://github.com/spree/spree.git")
        end
      end
    end

    describe "#github", :bundler => "4" do
      it "from github" do
        expect do
          spree_gems = %w[spree_core spree_api spree_backend]
          subject.github "spree" do
            spree_gems.each {|spree_gem| subject.send :gem, spree_gem }
          end
        end.to raise_error(Bundler::DeprecatedError, /github method has been removed/)
      end
    end
  end

  describe "syntax errors" do
    it "will raise a Bundler::GemfileError" do
      gemfile "gem 'foo', :path => /unquoted/string/syntax/error"
      expect { Bundler::Dsl.evaluate(bundled_app("Gemfile"), nil, true) }.
        to raise_error(Bundler::GemfileError, /There was an error parsing `Gemfile`:( compile error -)? unknown regexp options - trg. Bundler cannot continue./)
    end
  end

  describe "Runtime errors", :unless => Bundler.current_ruby.on_18? do
    it "will raise a Bundler::GemfileError" do
      gemfile "s = 'foo'.freeze; s.strip!"
      expect { Bundler::Dsl.evaluate(bundled_app("Gemfile"), nil, true) }.
        to raise_error(Bundler::GemfileError, /There was an error parsing `Gemfile`: can't modify frozen String. Bundler cannot continue./i)
    end
  end

  describe "#with_source" do
    context "if there was a rubygem source already defined" do
      it "restores it after it's done" do
        other_source = double("other-source")
        allow(Bundler::Source::Rubygems).to receive(:new).and_return(other_source)
        allow(Bundler).to receive(:default_gemfile).and_return(Pathname.new("./Gemfile"))

        subject.source("https://other-source.org") do
          subject.gem("dobry-pies", :path => "foo")
          subject.gem("foo")
        end

        expect(subject.dependencies.last.source).to eq(other_source)
      end
    end
  end
end
