require_relative '../spec_helper'

describe :resists_cve_2011_4815, shared: true do
  it "resists CVE-2011-4815 by having different hash codes in different processes" do
    eval("(#{@method}).hash.to_s").should_not == ruby_exe("print (#{@method}).hash")
  end
end

describe "Object#hash" do
  it_behaves_like :resists_cve_2011_4815, 'Object.new'
end

describe "Integer#hash with a small value" do
  it_behaves_like :resists_cve_2011_4815, '14'
end

describe "Integer#hash with a large value" do
  it_behaves_like :resists_cve_2011_4815, '100000000000000000000000000000'
end

describe "Float#hash" do
  it_behaves_like :resists_cve_2011_4815, '3.14'
end

describe "Rational#hash" do
  it_behaves_like :resists_cve_2011_4815, 'Rational(1, 2)'
end

describe "Complex#hash" do
  it_behaves_like :resists_cve_2011_4815, 'Complex(1, 2)'
end

describe "String#hash" do
  it_behaves_like :resists_cve_2011_4815, '"abc"'
end

describe "Symbol#hash" do
  it_behaves_like :resists_cve_2011_4815, ':a'
end

describe "Array#hash" do
  it_behaves_like :resists_cve_2011_4815, '[1, 2, 3]'
end

describe "Hash#hash" do
  it_behaves_like :resists_cve_2011_4815, '{a: 1, b: 2, c: 3}'
end
