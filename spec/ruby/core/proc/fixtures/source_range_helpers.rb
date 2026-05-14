def source_range_values(range)
  [range.start_line, range.start_column, range.end_line, range.end_column]
end

# Use <<-RUBY and not <<~RUBY to keep some spaces in front to make it more representative of a Proc in some file
def check_source_range(source)
  raise "Expected 2 '$' to mark start and end of source_range" unless source.count('$') == 2
  from = source.byteindex('$')
  to = source.byteindex('$', from+1)
  lines = source.lines
  from_line = 1 + source.byteslice(0, from).count("\n")
  from_column = lines[from_line-1].byteindex('$')
  to_line = 1 + source.byteslice(0, to).count("\n")
  if from_line == to_line
    to_column = lines[to_line-1].byteindex('$', from_column + 1) - 1
  else
    to_column = lines[to_line-1].byteindex('$')
  end

  eval_source = source.gsub('$', '')
  result = eval(eval_source)
  source_range = result.source_range
  source_range.should.instance_of?(Ruby::SourceRange)
  source_range.start_line.should == from_line
  source_range.start_column.should == from_column
  source_range.end_line.should == to_line
  source_range.end_column.should == to_column

  # Check consistency with source_location start line
  result.source_location[1].should == from_line
end
