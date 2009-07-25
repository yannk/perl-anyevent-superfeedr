use strict;
use warnings;
use Find::Lib '../lib';
use AnyEvent::Superfeedr;
use Encode;

die "$0 <jid> <pass>" unless @ARGV >= 2;

binmode STDOUT, ":utf8";

my $end = AnyEvent->condvar;
my $sf = AnyEvent::Superfeedr->new(
    jid => shift,
    password => shift,
    #subscription => {
    #    interval => 5,
    #    cb => sub { [ "http://blog.cyberion.net/atom.xml"] },
    #},
    on_notification => sub { 
        my $entry = shift;
        my $title = Encode::decode_utf8($entry->title); 
        $title =~ s/\s+/ /gs;

        my $l = length $title;
        my $max = 50;
        if ($l > $max) {
            substr $title, $max - 3, $l - $max + 3, '...';
        }
        printf "~ %-50s\n", $title;
    },
);
$end->recv;
