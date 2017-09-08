# frozen_string_literal: true
require "spec_helper"

RSpec.describe Bundler::Plugin::SourceList do
  SourceList = Bundler::Plugin::SourceList

  before do
    allow(Bundler).to receive(:root) { Pathname.new "/" }
  end

  subject(:source_list) { SourceList.new }

  describe "adding sources uses classes for plugin" do
    it "uses Plugin::Installer::Rubygems for rubygems sources" do
      source = source_list.
        add_rubygems_source("remotes" => ["https://existing-rubygems.org"])
      expect(source).to be_instance_of(Bundler::Plugin::Installer::Rubygems)
    end

    it "uses Plugin::Installer::Git for git sources" do
      source = source_list.
        add_git_source("uri" => "git://existing-git.org/path.git")
      expect(source).to be_instance_of(Bundler::Plugin::Installer::Git)
    end
  end
end
