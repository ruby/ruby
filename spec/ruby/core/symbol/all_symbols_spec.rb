require_relative '../../spec_helper'

describe "Symbol.all_symbols" do
  it "returns an array of Symbols" do
    all_symbols = Symbol.all_symbols
    all_symbols.should be_an_instance_of(Array)
    all_symbols.each { |s| s.should be_an_instance_of(Symbol) }
  end

  it "includes symbols that are strongly referenced" do
    symbol = "symbol_specs_#{rand(5_000_000)}".to_sym
    Symbol.all_symbols.should include(symbol)
  end

  it "includes symbols that are referenced in source code but not yet executed" do
    Symbol.all_symbols.any? { |s| s.to_s == 'symbol_specs_referenced_in_source_code' }.should be_true
    :symbol_specs_referenced_in_source_code
  end
end
