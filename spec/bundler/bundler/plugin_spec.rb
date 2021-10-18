# frozen_string_literal: true

RSpec.describe Bundler::Plugin do
  Plugin = Bundler::Plugin

  let(:installer) { double(:installer) }
  let(:index) { double(:index) }
  let(:spec) { double(:spec) }
  let(:spec2) { double(:spec2) }

  before do
    build_lib "new-plugin", path: lib_path("new-plugin") do |s|
      s.write "plugins.rb"
    end

    build_lib "another-plugin", path: lib_path("another-plugin") do |s|
      s.write "plugins.rb"
    end

    allow(spec).to receive(:full_gem_path).
      and_return(lib_path("new-plugin").to_s)
    allow(spec).to receive(:load_paths).
      and_return([lib_path("new-plugin").join("lib").to_s])

    allow(spec2).to receive(:full_gem_path).
      and_return(lib_path("another-plugin").to_s)
    allow(spec2).to receive(:load_paths).
      and_return([lib_path("another-plugin").join("lib").to_s])

    allow(Plugin::Installer).to receive(:new) { installer }
    allow(Plugin).to receive(:index) { index }
    allow(index).to receive(:register_plugin)
  end

  describe "list command" do
    context "when no plugins are installed" do
      before { allow(index).to receive(:installed_plugins) { [] } }
      it "outputs no plugins installed" do
        expect(Bundler.ui).to receive(:info).with("No plugins installed")
        subject.list
      end
    end

    context "with installed plugins" do
      before do
        allow(index).to receive(:installed_plugins) { %w[plug1 plug2] }
        allow(index).to receive(:plugin_commands).with("plug1") { %w[c11 c12] }
        allow(index).to receive(:plugin_commands).with("plug2") { %w[c21 c22] }
      end
      it "list plugins followed by commands" do
        expected_output = "plug1\n-----\n  c11\n  c12\n\nplug2\n-----\n  c21\n  c22\n\n"
        expect(Bundler.ui).to receive(:info).with(expected_output)
        subject.list
      end
    end
  end

  describe "install command" do
    let(:opts) { { "version" => "~> 1.0", "source" => "foo" } }

    before do
      allow(installer).to receive(:install).with(["new-plugin"], opts) do
        { "new-plugin" => spec }
      end
    end

    it "passes the name and options to installer" do
      allow(index).to receive(:installed?).
        with("new-plugin")
      allow(installer).to receive(:install).with(["new-plugin"], opts) do
        { "new-plugin" => spec }
      end.once

      subject.install ["new-plugin"], opts
    end

    it "validates the installed plugin" do
      allow(index).to receive(:installed?).
        with("new-plugin")
      allow(subject).
        to receive(:validate_plugin!).with(lib_path("new-plugin")).once

      subject.install ["new-plugin"], opts
    end

    it "registers the plugin with index" do
      allow(index).to receive(:installed?).
        with("new-plugin")
      allow(index).to receive(:register_plugin).
        with("new-plugin", lib_path("new-plugin").to_s, [lib_path("new-plugin").join("lib").to_s], []).once
      subject.install ["new-plugin"], opts
    end

    context "multiple plugins" do
      it do
        allow(installer).to receive(:install).
          with(["new-plugin", "another-plugin"], opts) do
          {
            "new-plugin" => spec,
            "another-plugin" => spec2,
          }
        end.once

        allow(subject).to receive(:validate_plugin!).twice
        allow(index).to receive(:installed?).twice
        allow(index).to receive(:register_plugin).twice
        subject.install ["new-plugin", "another-plugin"], opts
      end
    end
  end

  describe "evaluate gemfile for plugins" do
    let(:definition) { double("definition") }
    let(:builder) { double("builder") }
    let(:gemfile) { bundled_app_gemfile }

    before do
      allow(Plugin::DSL).to receive(:new) { builder }
      allow(builder).to receive(:eval_gemfile).with(gemfile)
      allow(builder).to receive(:check_primary_source_safety)
      allow(builder).to receive(:to_definition) { definition }
      allow(builder).to receive(:inferred_plugins) { [] }
    end

    it "doesn't calls installer without any plugins" do
      allow(definition).to receive(:dependencies) { [] }
      allow(installer).to receive(:install_definition).never

      subject.gemfile_install(gemfile)
    end

    context "with dependencies" do
      let(:plugin_specs) do
        {
          "new-plugin" => spec,
          "another-plugin" => spec2,
        }
      end

      before do
        allow(index).to receive(:installed?) { nil }
        allow(definition).to receive(:dependencies) { [Bundler::Dependency.new("new-plugin", ">=0"), Bundler::Dependency.new("another-plugin", ">=0")] }
        allow(installer).to receive(:install_definition) { plugin_specs }
      end

      it "should validate and register the plugins" do
        expect(subject).to receive(:validate_plugin!).twice
        expect(subject).to receive(:register_plugin).twice

        subject.gemfile_install(gemfile)
      end

      it "should pass the optional plugins to #register_plugin" do
        allow(builder).to receive(:inferred_plugins) { ["another-plugin"] }

        expect(subject).to receive(:register_plugin).
          with("new-plugin", spec, false).once

        expect(subject).to receive(:register_plugin).
          with("another-plugin", spec2, true).once

        subject.gemfile_install(gemfile)
      end
    end
  end

  describe "#command?" do
    it "returns true value for commands in index" do
      allow(index).
        to receive(:command_plugin).with("newcommand") { "my-plugin" }
      result = subject.command? "newcommand"
      expect(result).to be_truthy
    end

    it "returns false value for commands not in index" do
      allow(index).to receive(:command_plugin).with("newcommand") { nil }
      result = subject.command? "newcommand"
      expect(result).to be_falsy
    end
  end

  describe "#exec_command" do
    it "raises UndefinedCommandError when command is not found" do
      allow(index).to receive(:command_plugin).with("newcommand") { nil }
      expect { subject.exec_command("newcommand", []) }.
        to raise_error(Plugin::UndefinedCommandError)
    end
  end

  describe "#source?" do
    it "returns true value for sources in index" do
      allow(index).
        to receive(:command_plugin).with("foo-source") { "my-plugin" }
      result = subject.command? "foo-source"
      expect(result).to be_truthy
    end

    it "returns false value for source not in index" do
      allow(index).to receive(:command_plugin).with("foo-source") { nil }
      result = subject.command? "foo-source"
      expect(result).to be_falsy
    end
  end

  describe "#source" do
    it "raises UnknownSourceError when source is not found" do
      allow(index).to receive(:source_plugin).with("bar") { nil }
      expect { subject.source("bar") }.
        to raise_error(Plugin::UnknownSourceError)
    end

    it "loads the plugin, if not loaded" do
      allow(index).to receive(:source_plugin).with("foo-bar") { "plugin_name" }

      expect(subject).to receive(:load_plugin).with("plugin_name")
      subject.source("foo-bar")
    end

    it "returns the class registered with #add_source" do
      allow(index).to receive(:source_plugin).with("foo") { "plugin_name" }
      stub_const "NewClass", Class.new

      subject.add_source("foo", NewClass)
      expect(subject.source("foo")).to be(NewClass)
    end
  end

  describe "#from_lock" do
    it "returns instance of registered class initialized with locked opts" do
      opts = { "type" => "l_source", "remote" => "xyz", "other" => "random" }
      allow(index).to receive(:source_plugin).with("l_source") { "plugin_name" }

      stub_const "SClass", Class.new
      s_instance = double(:s_instance)
      subject.add_source("l_source", SClass)

      expect(SClass).to receive(:new).
        with(hash_including("type" => "l_source", "uri" => "xyz", "other" => "random")) { s_instance }
      expect(subject.from_lock(opts)).to be(s_instance)
    end
  end

  describe "#root" do
    context "in app dir" do
      before do
        allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      end

      it "returns plugin dir in app .bundle path" do
        expect(subject.root).to eq(bundled_app(".bundle/plugin"))
      end
    end

    context "outside app dir" do
      before do
        allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(nil)
      end

      it "returns plugin dir in global bundle path" do
        expect(subject.root).to eq(home.join(".bundle/plugin"))
      end
    end
  end

  describe "#add_hook" do
    it "raises an ArgumentError on an unregistered event" do
      ran = false
      expect do
        Plugin.add_hook("unregistered-hook") { ran = true }
      end.to raise_error(ArgumentError)
      expect(ran).to be(false)
    end
  end

  describe "#hook" do
    before do
      path = lib_path("foo-plugin")
      build_lib "foo-plugin", path: path do |s|
        s.write "plugins.rb", code
      end

      Bundler::Plugin::Events.send(:reset)
      Bundler::Plugin::Events.send(:define, :EVENT1, "event-1")
      Bundler::Plugin::Events.send(:define, :EVENT2, "event-2")

      allow(index).to receive(:hook_plugins).with(Bundler::Plugin::Events::EVENT1).
        and_return(["foo-plugin", "", nil])
      allow(index).to receive(:hook_plugins).with(Bundler::Plugin::Events::EVENT2).
        and_return(["foo-plugin"])
      allow(index).to receive(:plugin_path).with("foo-plugin").and_return(path)
      allow(index).to receive(:load_paths).with("foo-plugin").and_return([])
    end

    let(:code) { <<-RUBY }
      Bundler::Plugin::API.hook("event-1") { puts "hook for event 1" }
    RUBY

    it "raises an ArgumentError on an unregistered event" do
      expect do
        Plugin.hook("unregistered-hook")
      end.to raise_error(ArgumentError)
    end

    it "executes the hook" do
      expect do
        Plugin.hook(Bundler::Plugin::Events::EVENT1)
      end.to output("hook for event 1\n").to_stdout
    end

    context "single plugin declaring more than one hook" do
      let(:code) { <<-RUBY }
        Bundler::Plugin::API.hook(Bundler::Plugin::Events::EVENT1) {}
        Bundler::Plugin::API.hook(Bundler::Plugin::Events::EVENT2) {}
        puts "loaded"
      RUBY

      it "evals plugins.rb once" do
        expect do
          Plugin.hook(Bundler::Plugin::Events::EVENT1)
          Plugin.hook(Bundler::Plugin::Events::EVENT2)
        end.to output("loaded\n").to_stdout
      end
    end

    context "a block is passed" do
      let(:code) { <<-RUBY }
        Bundler::Plugin::API.hook(Bundler::Plugin::Events::EVENT1) { |&blk| blk.call }
      RUBY

      it "is passed to the hook" do
        expect do
          Plugin.hook(Bundler::Plugin::Events::EVENT1) { puts "win" }
        end.to output("win\n").to_stdout
      end
    end
  end
end
