# frozen_string_literal: true

RSpec.describe "bundle viz", :bundler => "< 3", :if => Bundler.which("dot") do
  before do
    realworld_system_gems "ruby-graphviz --version 1.2.5"
  end

  it "graphs gems from the Gemfile" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack"
      gem "rack-obama"
    G

    bundle "viz"
    expect(out).to include("gem_graph.png")

    bundle "viz", :format => "debug"
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
      source "#{file_uri_for(gem_repo2)}"
      gem "rack", "= 1.3.pre"
      gem "rack-obama"
    G

    bundle "viz"
    expect(out).to include("gem_graph.png")

    bundle "viz", :format => :debug, :version => true
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

  context "with another gem that has a graphviz file" do
    before do
      build_repo4 do
        build_gem "graphviz", "999" do |s|
          s.write("lib/graphviz.rb", "abort 'wrong graphviz gem loaded'")
        end
      end

      system_gems "graphviz-999", :gem_repo => gem_repo4
    end

    it "loads the correct ruby-graphviz gem" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
        gem "rack-obama"
      G

      bundle "viz", :format => "debug"
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
  end

  context "--without option" do
    it "one group" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "activesupport"

        group :rails do
          gem "rails"
        end
      G

      bundle "viz --without=rails"
      expect(out).to include("gem_graph.png")
    end

    it "two groups" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "activesupport"

        group :rack do
          gem "rack"
        end

        group :rails do
          gem "rails"
        end
      G

      bundle "viz --without=rails:rack"
      expect(out).to include("gem_graph.png")
    end
  end
end
