package AnyEvent::Superfeedr::Notification;
use strict;
use warnings;
use XML::Atom::Entry;
use XML::Atom::Feed;
use URI();
use URI::tag();
use AnyEvent::Superfeedr();

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

sub as_atom_feed {
    my $notification = shift;
    my $feed = XML::Atom::Feed->new;
    for ($notification->entries) {
        $feed->add_entry($_);
    }
    return $feed;
}

sub as_xml {
    my $notification = shift;
    my $id = $notification->tagify;
    my $feed_uri = $notification->feed_uri;
    my $feed = <<EOX;
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://purl.org/atom/ns#">
<id>$id</id>
<link>$feed_uri</link>
EOX
    for my $item (@{ $notification->items}) {
        my ($entry) = $item->nodes;
        $feed .= $entry->as_string;
    }
    $feed .= "</feed>";
}

sub tagify {
    my $notification = shift;

    ## date is based on current time
    my (undef, undef, undef, $mday, $mon, $year) = gmtime();
    $year +=1900;

    ## specific is based on superfeedr's feed:status
    my $specific = $notification->feed_uri || "";
    $specific =~ s{^\w+://}{};
    $specific =~ tr{#}{/};

    my $tag = URI->new("tag:");
    $tag->authority($AnyEvent::Superfeedr::SERVICE);
    $tag->date(sprintf "%4d-%02d-%02d", $year, $mon, $mday);
    $tag->specific($specific);
    return $tag->as_string;
}

1;
