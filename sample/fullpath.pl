#! /usr/local/bin/perl
# convert ls-lR filename into fullpath.

$path = shift;
if (!defined $path) {
    $path = "";
}
elsif ($path !~ /\/$/) {
  $path .= "/"
}

while (<>) {
    if (/:$/) {
	chop; chop;
	$path = $_ . "/";
    } elsif (/^total/ || /^d/) {
	next;
    } elsif (/^(.*\d )(.+)$/) {
	print $1, $path, $2, "\n";
    }
}
    
