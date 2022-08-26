# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe "exe" do
    def exe_path
      root_dir.join("exe").join("syntax_suggest")
    end

    def exe(cmd)
      out = run!("#{exe_path} #{cmd}", raise_on_nonzero_exit: false)
      puts out if ENV["SYNTAX_SUGGEST_DEBUG"]
      out
    end

    it "prints the version" do
      out = exe("-v")
      expect(out.strip).to include(SyntaxSuggest::VERSION)
    end
  end
end
