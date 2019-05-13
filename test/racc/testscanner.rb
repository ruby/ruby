#
# racc scanner tester
#

require 'racc/raccs'


class ScanError < StandardError; end

def testdata( dir, argv )
  if argv.empty? then
    Dir.glob( dir + '/*' ) -
    Dir.glob( dir + '/*.swp' ) -
    [ dir + '/CVS' ]
  else
    argv.collect {|i| dir + '/' + i }
  end
end


if ARGV.delete '--print' then
  $raccs_print_type = true
  printonly = true
else
  printonly = false
end

testdata( File.dirname($0) + '/scandata', ARGV ).each do |file|
  $stderr.print File.basename(file) + ': '
  begin
    ok = File.read(file)
    s = Racc::GrammarFileScanner.new( ok )
    sym, (val, lineno) = s.scan
    if printonly then
      $stderr.puts
      $stderr.puts val
      next
    end

    val = '{' + val + "}\n"
    sym == :ACTION  or raise ScanError, 'is not action!'
    val == ok       or raise ScanError, "\n>>>\n#{ok}----\n#{val}<<<"

    $stderr.puts 'ok'
  rescue => err
    $stderr.puts 'fail (' + err.type.to_s + ')'
    $stderr.puts err.message
    $stderr.puts err.backtrace
    $stderr.puts
  end
end
