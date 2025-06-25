# frozen_string_literal: true

RSpec.describe "bundle viz", if: Bundler.which("dot") do
  before do
    realworld_system_gems "ruby-graphviz --version 1.2.5"
  end

  it "graphs gems from the Gemfile" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
      gem "myrack-obama"
    G

    bundle "viz"
    expect(out).to include("gem_graph.png")

    bundle "viz", format: "debug"
    expect(out).to eq(<<~DOT.strip)
      digraph Gemfile {
      concentrate = "true";
      normalize = "true";
      nodesep = "0.55";
      edge[ weight  =  "2"];
      node[ fontname  =  "Arial, Helvetica, SansSerif"];
      edge[ fontname  =  "Arial, Helvetica, SansSerif" , fontsize  =  "12"];
      default [style = "filled", fillcolor = "#B9B9D5", shape = "box3d", fontsize = "16", label = "default"];
      myrack [style = "filled", fillcolor = "#B9B9D5", label = "myrack"];
        default -> myrack [constraint = "false"];
      "myrack-obama" [style = "filled", fillcolor = "#B9B9D5", label = "myrack-obama"];
        default -> "myrack-obama" [constraint = "false"];
        "myrack-obama" -> myrack;
      }
      debugging bundle viz...
    DOT
  end

  it "graphs gems that are prereleases" do
    build_repo2 do
      build_gem "myrack", "1.3.pre"
    end

    install_gemfile <<-G
      source "https://gem.repo2"
      gem "myrack", "= 1.3.pre"
      gem "myrack-obama"
    G

    bundle "viz"
    expect(out).to include("gem_graph.png")

    bundle "viz", format: :debug, version: true
    expect(out).to eq(<<~EOS.strip)
      digraph Gemfile {
      concentrate = "true";
      normalize = "true";
      nodesep = "0.55";
      edge[ weight  =  "2"];
      node[ fontname  =  "Arial, Helvetica, SansSerif"];
      edge[ fontname  =  "Arial, Helvetica, SansSerif" , fontsize  =  "12"];
      default [style = "filled", fillcolor = "#B9B9D5", shape = "box3d", fontsize = "16", label = "default"];
      myrack [style = "filled", fillcolor = "#B9B9D5", label = "myrack\\n1.3.pre"];
        default -> myrack [constraint = "false"];
      "myrack-obama" [style = "filled", fillcolor = "#B9B9D5", label = "myrack-obama\\n1.0"];
        default -> "myrack-obama" [constraint = "false"];
        "myrack-obama" -> myrack;
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

      system_gems "graphviz-999", gem_repo: gem_repo4
    end

    it "loads the correct ruby-graphviz gem" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "myrack-obama"
      G

      bundle "viz", format: "debug"
      expect(out).to eq(<<~DOT.strip)
        digraph Gemfile {
        concentrate = "true";
        normalize = "true";
        nodesep = "0.55";
        edge[ weight  =  "2"];
        node[ fontname  =  "Arial, Helvetica, SansSerif"];
        edge[ fontname  =  "Arial, Helvetica, SansSerif" , fontsize  =  "12"];
        default [style = "filled", fillcolor = "#B9B9D5", shape = "box3d", fontsize = "16", label = "default"];
        myrack [style = "filled", fillcolor = "#B9B9D5", label = "myrack"];
          default -> myrack [constraint = "false"];
        "myrack-obama" [style = "filled", fillcolor = "#B9B9D5", label = "myrack-obama"];
          default -> "myrack-obama" [constraint = "false"];
          "myrack-obama" -> myrack;
        }
        debugging bundle viz...
      DOT
    end
  end

  context "--without option" do
    it "one group" do
      install_gemfile <<-G
        source "https://gem.repo1"
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
        source "https://gem.repo1"
        gem "activesupport"

        group :myrack do
          gem "myrack"
        end

        group :rails do
          gem "rails"
        end
      G

      bundle "viz --without=rails:myrack"
      expect(out).to include("gem_graph.png")
    end
  end
end
