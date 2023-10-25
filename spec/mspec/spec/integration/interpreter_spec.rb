require 'spec_helper'

RSpec.describe "The interpreter passed with -t" do
  it "is used in subprocess" do
    fixtures = "spec/fixtures"
    interpreter = "#{fixtures}/my_ruby"
    out, ret = run_mspec("run", "#{fixtures}/print_interpreter_spec.rb -t #{interpreter}")
    out = out.lines.map(&:chomp).reject { |line|
      line == 'RUBY_DESCRIPTION'
    }.take(3)
    expect(out).to eq([
      interpreter,
      interpreter,
      "CWD/#{interpreter}"
    ])
    expect(ret.success?).to eq(true)
  end
end
