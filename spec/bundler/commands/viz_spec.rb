# frozen_string_literal: true
require "spec_helper"

describe "bundle viz", :ruby => "1.9.3", :if => Bundler.which("dot") do
  let(:graphviz_lib) do
    graphviz_glob = base_system_gems.join("gems/ruby-graphviz*/lib")
    Dir[graphviz_glob].first
  end

  before do
    ENV["RUBYOPT"] = "-I #{graphviz_lib}"
  end

  it "graphs gems from the Gemfile" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
      gem "rack-obama"
    G

    bundle! "viz"
    expect(out).to include("gem_graph.png")

    bundle! "viz", :format => "debug"
    expect(out).to eq(strip_whitespace(<<-DOT).strip)
      digraph Gemfile {
      concentrate = "true";
      normalize = "true";
      nodesep = "0.55";
      edge[ weight  =  "2"];
      node[ fontname  =  "Arial, Helvetica, SansSerif"];
      edge[ fontname  =  "Arial, Helvetica, SansSerif" , fontsize  =  "12"];
      default [style = "filled", fillcolor = "#B9B9D5", shape = "box3d", fontsize = "16", label = "default"];
      rack [style = "filled", fillcolor = "#B9B9D5", label = "rack"];
        default -> rack [constraint = "false"];
      "rack-obama" [style = "filled", fillcolor = "#B9B9D5", label = "rack-obama"];
        default -> "rack-obama" [constraint = "false"];
        "rack-obama" -> rack;
      }
      debugging bundle viz...
    DOT
  end

  it "graphs gems that are prereleases" do
    build_repo2 do
      build_gem "rack", "1.3.pre"
    end

    install_gemfile <<-G
      source "file://#{gem_repo2}"
      gem "rack", "= 1.3.pre"
      gem "rack-obama"
    G

    bundle! "viz"
    expect(out).to include("gem_graph.png")

    bundle! "viz", :format => :debug, :version => true
    expect(out).to eq(strip_whitespace(<<-EOS).strip)
      digraph Gemfile {
      concentrate = "true";
      normalize = "true";
      nodesep = "0.55";
      edge[ weight  =  "2"];
      node[ fontname  =  "Arial, Helvetica, SansSerif"];
      edge[ fontname  =  "Arial, Helvetica, SansSerif" , fontsize  =  "12"];
      default [style = "filled", fillcolor = "#B9B9D5", shape = "box3d", fontsize = "16", label = "default"];
      rack [style = "filled", fillcolor = "#B9B9D5", label = "rack\\n1.3.pre"];
        default -> rack [constraint = "false"];
      "rack-obama" [style = "filled", fillcolor = "#B9B9D5", label = "rack-obama\\n1.0"];
        default -> "rack-obama" [constraint = "false"];
        "rack-obama" -> rack;
      }
      debugging bundle viz...
    EOS
  end

  context "--without option" do
    it "one group" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "activesupport"

        group :rails do
          gem "rails"
        end
      G

      bundle! "viz --without=rails"
      expect(out).to include("gem_graph.png")
    end

    it "two groups" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "activesupport"

        group :rack do
          gem "rack"
        end

        group :rails do
          gem "rails"
        end
      G

      bundle! "viz --without=rails:rack"
      expect(out).to include("gem_graph.png")
    end
  end
end
