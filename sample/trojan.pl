#! /usr/local/bin/perl
@path = split(/:/, $ENV{'PATH'});

foreach $dir (@path) {
    foreach $f (<$dir/*>) {	
	if (-f $f) {
	    ($dev,$ino,$mode) = stat($f);
	    printf("file %s is writale from other users\n", $f)
		if ($mode & 022);
	}
    }
}
