# frozen_string_literal: true

RSpec.describe Bundler::SourceList do
  before do
    allow(Bundler).to receive(:root) { Pathname.new "./tmp/bundled_app" }

    stub_const "ASourcePlugin", Class.new(Bundler::Plugin::API)
    ASourcePlugin.source "new_source"
    allow(Bundler::Plugin).to receive(:source?).with("new_source").and_return(true)
  end

  subject(:source_list) { Bundler::SourceList.new }

  let(:rubygems_aggregate) { Bundler::Source::Rubygems.new }
  let(:metadata_source) { Bundler::Source::Metadata.new }

  describe "adding sources" do
    before do
      source_list.add_path_source("path" => "/existing/path/to/gem")
      source_list.add_git_source("uri" => "git://existing-git.org/path.git")
      source_list.add_rubygems_source("remotes" => ["https://existing-rubygems.org"])
      source_list.add_plugin_source("new_source", "uri" => "https://some.url/a")
    end

    describe "#add_path_source" do
      before do
        @duplicate = source_list.add_path_source("path" => "/path/to/gem")
        @new_source = source_list.add_path_source("path" => "/path/to/gem")
      end

      it "returns the new path source" do
        expect(@new_source).to be_instance_of(Bundler::Source::Path)
      end

      it "passes the provided options to the new source" do
        expect(@new_source.options).to eq("path" => "/path/to/gem")
      end

      it "adds the source to the beginning of path_sources" do
        expect(source_list.path_sources.first).to equal(@new_source)
      end

      it "removes existing duplicates" do
        expect(source_list.path_sources).not_to include equal(@duplicate)
      end
    end

    describe "#add_git_source" do
      before do
        @duplicate = source_list.add_git_source("uri" => "git://host/path.git")
        @new_source = source_list.add_git_source("uri" => "git://host/path.git")
      end

      it "returns the new git source" do
        expect(@new_source).to be_instance_of(Bundler::Source::Git)
      end

      it "passes the provided options to the new source" do
        @new_source = source_list.add_git_source("uri" => "git://host/path.git")
        expect(@new_source.options).to eq("uri" => "git://host/path.git")
      end

      it "adds the source to the beginning of git_sources" do
        @new_source = source_list.add_git_source("uri" => "git://host/path.git")
        expect(source_list.git_sources.first).to equal(@new_source)
      end

      it "removes existing duplicates" do
        @duplicate = source_list.add_git_source("uri" => "git://host/path.git")
        @new_source = source_list.add_git_source("uri" => "git://host/path.git")
        expect(source_list.git_sources).not_to include equal(@duplicate)
      end

      context "with the git: protocol" do
        let(:msg) do
          "The git source `git://existing-git.org/path.git` " \
          "uses the `git` protocol, which transmits data without encryption. " \
          "Disable this warning with `bundle config set --local git.allow_insecure true`, " \
          "or switch to the `https` protocol to keep your data secure."
        end

        it "warns about git protocols" do
          expect(Bundler.ui).to receive(:warn).with(msg)
          source_list.add_git_source("uri" => "git://existing-git.org/path.git")
        end

        it "ignores git protocols on request" do
          Bundler.settings.temporary(:"git.allow_insecure" => true)
          expect(Bundler.ui).to_not receive(:warn).with(msg)
          source_list.add_git_source("uri" => "git://existing-git.org/path.git")
        end
      end
    end

    describe "#add_rubygems_source" do
      before do
        @duplicate = source_list.add_rubygems_source("remotes" => ["https://rubygems.org/"])
        @new_source = source_list.add_rubygems_source("remotes" => ["https://rubygems.org/"])
      end

      it "returns the new rubygems source" do
        expect(@new_source).to be_instance_of(Bundler::Source::Rubygems)
      end

      it "passes the provided options to the new source" do
        expect(@new_source.options).to eq("remotes" => ["https://rubygems.org/"])
      end

      it "adds the source to the beginning of rubygems_sources" do
        expect(source_list.rubygems_sources.first).to equal(@new_source)
      end

      it "removes duplicates" do
        expect(source_list.rubygems_sources).not_to include equal(@duplicate)
      end
    end

    describe "#add_rubygems_remote", :bundler => "< 3" do
      let!(:returned_source) { source_list.add_rubygems_remote("https://rubygems.org/") }

      it "returns the aggregate rubygems source" do
        expect(returned_source).to be_instance_of(Bundler::Source::Rubygems)
      end

      it "adds the provided remote to the beginning of the aggregate source" do
        source_list.add_rubygems_remote("https://othersource.org")
        expect(returned_source.remotes).to eq [
          Bundler::URI("https://othersource.org/"),
          Bundler::URI("https://rubygems.org/"),
        ]
      end
    end

    describe "#add_plugin_source" do
      before do
        @duplicate = source_list.add_plugin_source("new_source", "uri" => "http://host/path.")
        @new_source = source_list.add_plugin_source("new_source", "uri" => "http://host/path.")
      end

      it "returns the new plugin source" do
        expect(@new_source).to be_a(Bundler::Plugin::API::Source)
      end

      it "passes the provided options to the new source" do
        expect(@new_source.options).to eq("uri" => "http://host/path.")
      end

      it "adds the source to the beginning of git_sources" do
        expect(source_list.plugin_sources.first).to equal(@new_source)
      end

      it "removes existing duplicates" do
        expect(source_list.plugin_sources).not_to include equal(@duplicate)
      end
    end
  end

  describe "#all_sources" do
    it "includes the aggregate rubygems source when rubygems sources have been added" do
      source_list.add_git_source("uri" => "git://host/path.git")
      source_list.add_rubygems_source("remotes" => ["https://rubygems.org"])
      source_list.add_path_source("path" => "/path/to/gem")
      source_list.add_plugin_source("new_source", "uri" => "https://some.url/a")

      expect(source_list.all_sources).to include rubygems_aggregate
    end

    it "includes the aggregate rubygems source when no rubygems sources have been added" do
      source_list.add_git_source("uri" => "git://host/path.git")
      source_list.add_path_source("path" => "/path/to/gem")
      source_list.add_plugin_source("new_source", "uri" => "https://some.url/a")

      expect(source_list.all_sources).to include rubygems_aggregate
    end

    it "returns sources of the same type in the reverse order that they were added" do
      source_list.add_git_source("uri" => "git://third-git.org/path.git")
      source_list.add_rubygems_source("remotes" => ["https://fifth-rubygems.org"])
      source_list.add_path_source("path" => "/third/path/to/gem")
      source_list.add_plugin_source("new_source", "uri" => "https://some.url/b")
      source_list.add_rubygems_source("remotes" => ["https://fourth-rubygems.org"])
      source_list.add_path_source("path" => "/second/path/to/gem")
      source_list.add_rubygems_source("remotes" => ["https://third-rubygems.org"])
      source_list.add_plugin_source("new_source", "uri" => "https://some.o.url/")
      source_list.add_git_source("uri" => "git://second-git.org/path.git")
      source_list.add_rubygems_source("remotes" => ["https://second-rubygems.org"])
      source_list.add_path_source("path" => "/first/path/to/gem")
      source_list.add_plugin_source("new_source", "uri" => "https://some.url/c")
      source_list.add_rubygems_source("remotes" => ["https://first-rubygems.org"])
      source_list.add_git_source("uri" => "git://first-git.org/path.git")

      expect(source_list.all_sources).to eq [
        Bundler::Source::Path.new("path" => "/first/path/to/gem"),
        Bundler::Source::Path.new("path" => "/second/path/to/gem"),
        Bundler::Source::Path.new("path" => "/third/path/to/gem"),
        Bundler::Source::Git.new("uri" => "git://first-git.org/path.git"),
        Bundler::Source::Git.new("uri" => "git://second-git.org/path.git"),
        Bundler::Source::Git.new("uri" => "git://third-git.org/path.git"),
        ASourcePlugin.new("uri" => "https://some.url/c"),
        ASourcePlugin.new("uri" => "https://some.o.url/"),
        ASourcePlugin.new("uri" => "https://some.url/b"),
        Bundler::Source::Rubygems.new("remotes" => ["https://first-rubygems.org"]),
        Bundler::Source::Rubygems.new("remotes" => ["https://second-rubygems.org"]),
        Bundler::Source::Rubygems.new("remotes" => ["https://third-rubygems.org"]),
        Bundler::Source::Rubygems.new("remotes" => ["https://fourth-rubygems.org"]),
        Bundler::Source::Rubygems.new("remotes" => ["https://fifth-rubygems.org"]),
        rubygems_aggregate,
        metadata_source,
      ]
    end
  end

  describe "#path_sources" do
    it "returns an empty array when no path sources have been added" do
      source_list.add_rubygems_remote("https://rubygems.org")
      source_list.add_git_source("uri" => "git://host/path.git")
      expect(source_list.path_sources).to be_empty
    end

    it "returns path sources in the reverse order that they were added" do
      source_list.add_git_source("uri" => "git://third-git.org/path.git")
      source_list.add_rubygems_remote("https://fifth-rubygems.org")
      source_list.add_path_source("path" => "/third/path/to/gem")
      source_list.add_rubygems_remote("https://fourth-rubygems.org")
      source_list.add_path_source("path" => "/second/path/to/gem")
      source_list.add_rubygems_remote("https://third-rubygems.org")
      source_list.add_git_source("uri" => "git://second-git.org/path.git")
      source_list.add_rubygems_remote("https://second-rubygems.org")
      source_list.add_path_source("path" => "/first/path/to/gem")
      source_list.add_rubygems_remote("https://first-rubygems.org")
      source_list.add_git_source("uri" => "git://first-git.org/path.git")

      expect(source_list.path_sources).to eq [
        Bundler::Source::Path.new("path" => "/first/path/to/gem"),
        Bundler::Source::Path.new("path" => "/second/path/to/gem"),
        Bundler::Source::Path.new("path" => "/third/path/to/gem"),
      ]
    end
  end

  describe "#git_sources" do
    it "returns an empty array when no git sources have been added" do
      source_list.add_rubygems_remote("https://rubygems.org")
      source_list.add_path_source("path" => "/path/to/gem")

      expect(source_list.git_sources).to be_empty
    end

    it "returns git sources in the reverse order that they were added" do
      source_list.add_git_source("uri" => "git://third-git.org/path.git")
      source_list.add_rubygems_remote("https://fifth-rubygems.org")
      source_list.add_path_source("path" => "/third/path/to/gem")
      source_list.add_rubygems_remote("https://fourth-rubygems.org")
      source_list.add_path_source("path" => "/second/path/to/gem")
      source_list.add_rubygems_remote("https://third-rubygems.org")
      source_list.add_git_source("uri" => "git://second-git.org/path.git")
      source_list.add_rubygems_remote("https://second-rubygems.org")
      source_list.add_path_source("path" => "/first/path/to/gem")
      source_list.add_rubygems_remote("https://first-rubygems.org")
      source_list.add_git_source("uri" => "git://first-git.org/path.git")

      expect(source_list.git_sources).to eq [
        Bundler::Source::Git.new("uri" => "git://first-git.org/path.git"),
        Bundler::Source::Git.new("uri" => "git://second-git.org/path.git"),
        Bundler::Source::Git.new("uri" => "git://third-git.org/path.git"),
      ]
    end
  end

  describe "#plugin_sources" do
    it "returns an empty array when no plugin sources have been added" do
      source_list.add_rubygems_remote("https://rubygems.org")
      source_list.add_path_source("path" => "/path/to/gem")

      expect(source_list.plugin_sources).to be_empty
    end

    it "returns plugin sources in the reverse order that they were added" do
      source_list.add_plugin_source("new_source", "uri" => "https://third-git.org/path.git")
      source_list.add_git_source("https://new-git.org")
      source_list.add_path_source("path" => "/third/path/to/gem")
      source_list.add_rubygems_remote("https://fourth-rubygems.org")
      source_list.add_path_source("path" => "/second/path/to/gem")
      source_list.add_rubygems_remote("https://third-rubygems.org")
      source_list.add_plugin_source("new_source", "uri" => "git://second-git.org/path.git")
      source_list.add_rubygems_remote("https://second-rubygems.org")
      source_list.add_path_source("path" => "/first/path/to/gem")
      source_list.add_rubygems_remote("https://first-rubygems.org")
      source_list.add_plugin_source("new_source", "uri" => "git://first-git.org/path.git")

      expect(source_list.plugin_sources).to eq [
        ASourcePlugin.new("uri" => "git://first-git.org/path.git"),
        ASourcePlugin.new("uri" => "git://second-git.org/path.git"),
        ASourcePlugin.new("uri" => "https://third-git.org/path.git"),
      ]
    end
  end

  describe "#rubygems_sources" do
    it "includes the aggregate rubygems source when rubygems sources have been added" do
      source_list.add_git_source("uri" => "git://host/path.git")
      source_list.add_rubygems_source("remotes" => ["https://rubygems.org"])
      source_list.add_path_source("path" => "/path/to/gem")

      expect(source_list.rubygems_sources).to include rubygems_aggregate
    end

    it "returns only the aggregate rubygems source when no rubygems sources have been added" do
      source_list.add_git_source("uri" => "git://host/path.git")
      source_list.add_path_source("path" => "/path/to/gem")

      expect(source_list.rubygems_sources).to eq [rubygems_aggregate]
    end

    it "returns rubygems sources in the reverse order that they were added" do
      source_list.add_git_source("uri" => "git://third-git.org/path.git")
      source_list.add_rubygems_source("remotes" => ["https://fifth-rubygems.org"])
      source_list.add_path_source("path" => "/third/path/to/gem")
      source_list.add_rubygems_source("remotes" => ["https://fourth-rubygems.org"])
      source_list.add_path_source("path" => "/second/path/to/gem")
      source_list.add_rubygems_source("remotes" => ["https://third-rubygems.org"])
      source_list.add_git_source("uri" => "git://second-git.org/path.git")
      source_list.add_rubygems_source("remotes" => ["https://second-rubygems.org"])
      source_list.add_path_source("path" => "/first/path/to/gem")
      source_list.add_rubygems_source("remotes" => ["https://first-rubygems.org"])
      source_list.add_git_source("uri" => "git://first-git.org/path.git")

      expect(source_list.rubygems_sources).to eq [
        Bundler::Source::Rubygems.new("remotes" => ["https://first-rubygems.org"]),
        Bundler::Source::Rubygems.new("remotes" => ["https://second-rubygems.org"]),
        Bundler::Source::Rubygems.new("remotes" => ["https://third-rubygems.org"]),
        Bundler::Source::Rubygems.new("remotes" => ["https://fourth-rubygems.org"]),
        Bundler::Source::Rubygems.new("remotes" => ["https://fifth-rubygems.org"]),
        rubygems_aggregate,
      ]
    end
  end

  describe "#get" do
    context "when it includes an equal source" do
      let(:rubygems_source) { Bundler::Source::Rubygems.new("remotes" => ["https://rubygems.org"]) }
      before { @equal_source = source_list.add_rubygems_remote("https://rubygems.org") }

      it "returns the equal source" do
        expect(source_list.get(rubygems_source)).to be @equal_source
      end
    end

    context "when it does not include an equal source" do
      let(:path_source) { Bundler::Source::Path.new("path" => "/path/to/gem") }

      it "returns nil" do
        expect(source_list.get(path_source)).to be_nil
      end
    end
  end

  describe "#lock_sources" do
    before do
      source_list.add_git_source("uri" => "git://third-git.org/path.git")
      source_list.add_rubygems_source("remotes" => ["https://duplicate-rubygems.org"])
      source_list.add_plugin_source("new_source", "uri" => "https://third-bar.org/foo")
      source_list.add_path_source("path" => "/third/path/to/gem")
      source_list.add_rubygems_source("remotes" => ["https://third-rubygems.org"])
      source_list.add_path_source("path" => "/second/path/to/gem")
      source_list.add_rubygems_source("remotes" => ["https://second-rubygems.org"])
      source_list.add_git_source("uri" => "git://second-git.org/path.git")
      source_list.add_rubygems_source("remotes" => ["https://first-rubygems.org"])
      source_list.add_plugin_source("new_source", "uri" => "https://second-plugin.org/random")
      source_list.add_path_source("path" => "/first/path/to/gem")
      source_list.add_rubygems_source("remotes" => ["https://duplicate-rubygems.org"])
      source_list.add_git_source("uri" => "git://first-git.org/path.git")
    end

    it "combines the rubygems sources into a single instance, removing duplicate remotes from the end", :bundler => "< 3" do
      expect(source_list.lock_sources).to eq [
        Bundler::Source::Git.new("uri" => "git://first-git.org/path.git"),
        Bundler::Source::Git.new("uri" => "git://second-git.org/path.git"),
        Bundler::Source::Git.new("uri" => "git://third-git.org/path.git"),
        ASourcePlugin.new("uri" => "https://second-plugin.org/random"),
        ASourcePlugin.new("uri" => "https://third-bar.org/foo"),
        Bundler::Source::Path.new("path" => "/first/path/to/gem"),
        Bundler::Source::Path.new("path" => "/second/path/to/gem"),
        Bundler::Source::Path.new("path" => "/third/path/to/gem"),
        Bundler::Source::Rubygems.new("remotes" => [
          "https://duplicate-rubygems.org",
          "https://first-rubygems.org",
          "https://second-rubygems.org",
          "https://third-rubygems.org",
        ]),
      ]
    end

    it "returns all sources, without combining rubygems sources", :bundler => "3" do
      expect(source_list.lock_sources).to eq [
        Bundler::Source::Git.new("uri" => "git://first-git.org/path.git"),
        Bundler::Source::Git.new("uri" => "git://second-git.org/path.git"),
        Bundler::Source::Git.new("uri" => "git://third-git.org/path.git"),
        ASourcePlugin.new("uri" => "https://second-plugin.org/random"),
        ASourcePlugin.new("uri" => "https://third-bar.org/foo"),
        Bundler::Source::Path.new("path" => "/first/path/to/gem"),
        Bundler::Source::Path.new("path" => "/second/path/to/gem"),
        Bundler::Source::Path.new("path" => "/third/path/to/gem"),
        Bundler::Source::Rubygems.new,
        Bundler::Source::Rubygems.new("remotes" => ["https://duplicate-rubygems.org"]),
        Bundler::Source::Rubygems.new("remotes" => ["https://first-rubygems.org"]),
        Bundler::Source::Rubygems.new("remotes" => ["https://second-rubygems.org"]),
        Bundler::Source::Rubygems.new("remotes" => ["https://third-rubygems.org"]),
      ]
    end
  end

  describe "replace_sources!" do
    let(:existing_locked_source) { Bundler::Source::Path.new("path" => "/existing/path") }
    let(:removed_locked_source)  { Bundler::Source::Path.new("path" => "/removed/path") }

    let(:locked_sources) { [existing_locked_source, removed_locked_source] }

    before do
      @existing_source = source_list.add_path_source("path" => "/existing/path")
      @new_source = source_list.add_path_source("path" => "/new/path")
      source_list.replace_sources!(locked_sources)
    end

    it "maintains the order and number of sources" do
      expect(source_list.path_sources).to eq [@new_source, @existing_source]
    end

    it "retains the same instance of the new source" do
      expect(source_list.path_sources[0]).to be @new_source
    end

    it "replaces the instance of the existing source" do
      expect(source_list.path_sources[1]).to be existing_locked_source
    end
  end

  describe "#cached!" do
    let(:rubygems_source) { source_list.add_rubygems_source("remotes" => ["https://rubygems.org"]) }
    let(:git_source)      { source_list.add_git_source("uri" => "git://host/path.git") }
    let(:path_source)     { source_list.add_path_source("path" => "/path/to/gem") }

    it "calls #cached! on all the sources" do
      expect(rubygems_source).to receive(:cached!)
      expect(git_source).to receive(:cached!)
      expect(path_source).to receive(:cached!)
      source_list.cached!
    end
  end

  describe "#remote!" do
    let(:rubygems_source) { source_list.add_rubygems_source("remotes" => ["https://rubygems.org"]) }
    let(:git_source)      { source_list.add_git_source("uri" => "git://host/path.git") }
    let(:path_source)     { source_list.add_path_source("path" => "/path/to/gem") }

    it "calls #remote! on all the sources" do
      expect(rubygems_source).to receive(:remote!)
      expect(git_source).to receive(:remote!)
      expect(path_source).to receive(:remote!)
      source_list.remote!
    end
  end
end
