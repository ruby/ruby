#!/usr/bin/ruby
require 'test/unit'
require 'stringio'
require_relative '../sync_default_gems'

module Test_SyncDefaultGems
  class TestMessageFilter < Test::Unit::TestCase
    def assert_message_filter(expected, trailers, input, repo = "ruby/test", sha = "0123456789")
      subject, *expected = expected
      expected = [
        "[#{repo}] #{subject}\n",
        *expected.map {_1+"\n"},
        "\n",
        "https://github.com/#{repo}/commit/#{sha[0, 10]}\n",
      ]
      if trailers
        expected << "\n"
        expected.concat(trailers.map {_1+"\n"})
      end

      out, err = capture_output do
        SyncDefaultGems.message_filter(repo, sha, input: StringIO.new(input, "r"))
      end

      all_assertions do |a|
        a.for("error") {assert_empty err}
        a.for("result") {assert_pattern_list(expected, out)}
      end
    end

    def test_subject_only
      expected = [
        "initial commit",
      ]
      assert_message_filter(expected, nil, "initial commit")
    end

    def test_link_in_parenthesis
      expected = [
        "fix (https://github.com/ruby/test/pull/1)",
      ]
      assert_message_filter(expected, nil, "fix (#1)")
    end

    def test_co_authored_by
      expected = [
        "commit something",
      ]
      trailers = [
        "Co-Authored-By: git <git@ruby-lang.org>",
      ]
      assert_message_filter(expected, trailers, [expected, "", trailers, ""].join("\n"))
    end

    def test_multiple_co_authored_by
      expected = [
        "many commits",
      ]
      trailers = [
        "Co-authored-by: git <git@ruby-lang.org>",
        "Co-authored-by: svn <svn@ruby-lang.org>",
      ]
      assert_message_filter(expected, trailers, [expected, "", trailers, ""].join("\n"))
    end

    def test_co_authored_by_no_newline
      expected = [
        "commit something",
      ]
      trailers = [
        "Co-Authored-By: git <git@ruby-lang.org>",
      ]
      assert_message_filter(expected, trailers, [expected, "", trailers].join("\n"))
    end
  end

  class TestSyncWithCommits < Test::Unit::TestCase
    def setup
      super
      @target = nil
      pend "No git" unless system("git --version", out: IO::NULL)
      @testdir = Dir.mktmpdir("sync")
      @git_config = %W"HOME GIT_CONFIG_GLOBAL".each_with_object({}) {|k, c| c[k] = ENV[k]}
      ENV["HOME"] = @testdir
      ENV["GIT_CONFIG_GLOBAL"] = @testdir + "/gitconfig"
      system(*%W"git config --global user.email test@ruby-lang.org")
      system(*%W"git config --global user.name", "Ruby")
      system(*%W"git config --global init.defaultBranch default")
      @target = "sync-test"
      SyncDefaultGems::REPOSITORIES[@target.to_sym] = ["ruby/#{@target}", "default"]
      @sha = {}
      @origdir = Dir.pwd
      Dir.chdir(@testdir)
      ["src", @target].each do |dir|
        system(*%W"git init -q #{dir}", exception: true)
        Dir.mkdir("#{dir}/tool")
        File.write("#{dir}/tool/ok", "#!/bin/sh\n""echo ok\n")
        system(*%W"git add tool/ok", exception: true, chdir: dir)
        system(*%W"git commit -q -m", "Add tool #{dir}", exception: true, chdir: dir)
        @sha[dir] = IO.popen(%W[git log --format=%H -1], chdir: dir, &:read).chomp
      end
      system(*%W"git remote add #{@target} ../#{@target}", exception: true, chdir: "src")
    end

    def teardown
      if @target
        Dir.chdir(@origdir)
        SyncDefaultGems::REPOSITORIES.delete(@target.to_sym)
        ENV.update(@git_config)
        FileUtils.rm_rf(@testdir)
      end
      super
    end

    def capture_process_output_to(outputs)
      IO.pipe do |r, w|
        orig = outputs.map {|out| out.dup}
        outputs.each {|out| out.reopen(w)}
        w.close
        reader = Thread.start {r.read}
        yield
      ensure
        outputs.each {|out| o = orig.shift; out.reopen(o); o.close}
        return reader.value
      end
    end

    def capture_process_outputs
      out = err = nil
      synchronize do
        out = capture_process_output_to(STDOUT) do
          err = capture_process_output_to(STDERR) do
            yield
          end
        end
      end
      return out, err
    end

    def test_skip_tool
      system(*%W"git rm -q tool/ok", exception: true, chdir: @target)
      system(*%W"git commit -q -m", "Remove tool", exception: true, chdir: @target)
      out = capture_process_output_to([STDOUT, STDERR]) do
        Dir.chdir("src") do
          SyncDefaultGems.sync_default_gems_with_commits(@target, true)
        end
      end
      assert_equal(@sha["src"], IO.popen(%W[git log --format=%H -1], chdir: "src", &:read).chomp, out)
    end
  end
end
