# $Id$

RUBY=${RUBY:-ruby}
status=0

$RUBY tools/list-parse-event-ids.rb parse.y | awk '{print "on__" $1}' > list_a
$RUBY test/list-called-events.rb | sort -u > list_b
diff -u list_a list_b | grep '^-on' | sed 's/^-on__//' > list_diff
if [ -s list_diff ]
then
    cat list_diff
    status=1
fi
rm -f list_a list_b list_diff
exit $status
