$SIG{'INT'} = 'test';

while (<>) {
  print;
}
sub test { print "C-c handled\n"; }
