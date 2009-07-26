package AnyEvent::XMPP::Ext::Superfeedr;
use strict;
use warnings;

use AnyEvent::Superfeedr::Notification;
use base qw/AnyEvent::XMPP::Ext::Pubsub/;

use constant NS => 'http://superfeedr.com/xmpp-pubsub-ext';

=pod

Fires up Pubsub event's plus 2 new events:

=over 4

=item superfeedr_status( $status_hash )

A hash with the content of status

=item superfeedr_notification( $notification

A L<AnyEvent::Superfeedr::Notification> object.

=back

=cut

sub handle_incoming_pubsub_event {
    my ($self, $node) = @_;

    my (@items, $status_node);
    my ($code, $next_fetch, $feed_uri);

    if ( ($status_node) = $node->find_all([NS, 'status'])) {
        my ($http_node)       = $status_node->find_all([NS, 'http' ]);
        my ($next_fetch_node) = $status_node->find_all([NS, 'next_fetch' ]);

        $code       = $http_node       ? $http_node->attr('code') : undef;
        $next_fetch = $next_fetch_node ? $next_fetch_node->text   : undef;
        $feed_uri   = $status_node->attr('feed');

        my $status = {
            http_status => $code,
            next_fecth  => $next_fetch,
            feed_uri    => $feed_uri,
        };
        $self->event(superfeedr_status => $status);
    }
    if ( my ($q) = $node->find_all([qw/ pubsub_ev items /]) ) {
        foreach($q->find_all ([qw/pubsub_ev item/])) {
            push @items, $_;
        }
    }
    my $notification = AnyEvent::Superfeedr::Notification->new(
        http_status => $code,
        next_fetch  => $next_fetch,
        feed_uri    => $feed_uri,
        items       => [ @items ],
    );
    $self->event(pubsub_recv => @items);
    $self->event(superfeedr_notification => $notification);
}

1;
