require 'spec_helper'

RSpec.describe "Running mspec" do
  a_spec_output = <<EOS

1)
Foo#bar errors FAILED
Expected 1 == 2
to be truthy but was false
CWD/spec/fixtures/a_spec.rb:8:in `block (2 levels) in <top (required)>'
CWD/spec/fixtures/a_spec.rb:2:in `<top (required)>'

2)
Foo#bar fails ERROR
RuntimeError: failure
CWD/spec/fixtures/a_spec.rb:12:in `block (2 levels) in <top (required)>'
CWD/spec/fixtures/a_spec.rb:2:in `<top (required)>'

Finished in D.DDDDDD seconds
EOS

  a_stats = "1 file, 3 examples, 2 expectations, 1 failure, 1 error, 0 tagged\n"
  ab_stats = "2 files, 4 examples, 3 expectations, 1 failure, 1 error, 0 tagged\n"
  fixtures = "spec/fixtures"

  it "runs the specs" do
    out, ret = run_mspec("run", "#{fixtures}/a_spec.rb")
    expect(out).to eq("RUBY_DESCRIPTION\n.FE\n#{a_spec_output}\n#{a_stats}")
    expect(ret.success?).to eq(false)
  end

  it "directly with mspec-run runs the specs" do
    out, ret = run_mspec("-run", "#{fixtures}/a_spec.rb")
    expect(out).to eq("RUBY_DESCRIPTION\n.FE\n#{a_spec_output}\n#{a_stats}")
    expect(ret.success?).to eq(false)
  end

  it "runs the specs in parallel with -j using the dotted formatter" do
    out, ret = run_mspec("run", "-j #{fixtures}/a_spec.rb #{fixtures}/b_spec.rb")
    expect(out).to eq("RUBY_DESCRIPTION\n...\n#{a_spec_output}\n#{ab_stats}")
    expect(ret.success?).to eq(false)
  end

  it "runs the specs in parallel with -j -fa" do
    out, ret = run_mspec("run", "-j -fa #{fixtures}/a_spec.rb #{fixtures}/b_spec.rb")
    progress_bar =
      "\r[/ |                   0%                     | 00:00:00] \e[0;32m     0F \e[0;32m     0E\e[0m " +
      "\r[- | ==================50%                    | 00:00:00] \e[0;32m     0F \e[0;32m     0E\e[0m " +
      "\r[\\ | ==================100%================== | 00:00:00] \e[0;32m     0F \e[0;32m     0E\e[0m "
    expect(out).to eq("RUBY_DESCRIPTION\n#{progress_bar}\n#{a_spec_output}\n#{ab_stats}")
    expect(ret.success?).to eq(false)
  end

  it "gives a useful error message when a subprocess dies in parallel mode" do
    out, ret = run_mspec("run", "-j #{fixtures}/b_spec.rb #{fixtures}/die_spec.rb")
    lines = out.lines
    expect(lines).to include "A child mspec-run process died unexpectedly while running CWD/spec/fixtures/die_spec.rb\n"
    expect(lines).to include "Finished in D.DDDDDD seconds\n"
    expect(lines.last).to match(/^\d files?, \d examples?, \d expectations?, 0 failures, 0 errors, 0 tagged$/)
    expect(ret.success?).to eq(false)
  end

  it "gives a useful error message when a subprocess prints unexpected output on STDOUT in parallel mode" do
    out, ret = run_mspec("run", "-j #{fixtures}/b_spec.rb #{fixtures}/chatty_spec.rb")
    lines = out.lines
    expect(lines).to include "A child mspec-run process printed unexpected output on STDOUT: #{'"Hello\nIt\'s me!\n"'} while running CWD/spec/fixtures/chatty_spec.rb\n"
    expect(lines).to include "Finished in D.DDDDDD seconds\n"
    expect(lines.last).to eq("2 files, 2 examples, 2 expectations, 0 failures, 0 errors, 0 tagged\n")
    expect(ret.success?).to eq(false)
  end
end
