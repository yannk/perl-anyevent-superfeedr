package AnyEvent::Superfeedr::Notification;
use strict;
use warnings;
use XML::Atom::Entry;

use Object::Tiny qw{ http_status next_fetch feed_uri items _entries};

sub entries {
    my $notification = shift;
    my $entries = $notification->_entries;
    return @$entries if $entries;

    my @entries;
    for my $item (@{ $notification->items }) {
        ## each item as one entry
        my ($entry) = $item->nodes;
        ## there must be more efficient ways? XXX
        my $str = $entry->as_string;
        my $ae = XML::Atom::Entry->new(Stream => \$str);
        push @entries, $ae;
    }
    $notification->{items} = undef;
    $notification->{_entries} = \@entries;
    return @{ $notification->{_entries} };
}

1;
