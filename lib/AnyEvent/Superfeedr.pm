package AnyEvent::Superfeedr;

use strict;
use warnings;
use 5.008_001;

our $VERSION = '0.01';
use Carp;

use AnyEvent;
use AnyEvent::Superfeedr::Notification;
use AnyEvent::XMPP::Client;
use AnyEvent::XMPP::Ext::Superfeedr;
use AnyEvent::XMPP::Ext::Pubsub;
use XML::Atom::Entry;

use constant DEFAULT_SUB_IV => 60;

our $SERVICE = 'firehoser.superfeedr.com';

# TODO:
# debug
# tests
# on_error
# better error handling
# (maybe) pubsub

sub new {
    my $class = shift;
    my %param = @_;

    my %filtered;
    for ( qw{jid password debug subscription on_notification on_error} ) {
        $filtered{$_} = delete $param{$_};
    }
    croak "Unknown option(s): " . join ", ", keys %param if keys %param;

    my $superfeedr = bless {
        debug    => $filtered{debug} || 0,
        jid      => $filtered{jid},
        password => $filtered{password},
    }, ref $class || $class;

    if (my $s = $filtered{subscription}) {
        my $cb = $s->{cb}
            or croak "subscription needs to pass a 'cb' callback";
        my $iv = $s->{interval} || DEFAULT_SUB_IV;

        my $timer_cb = sub {
            my $list = $cb->($superfeedr);
            return unless $list && @$list;
            my $pubsub = $superfeedr->xmpp_pubsub;
            my $con    = $superfeedr->xmpp_connection;
            unless ($pubsub && $con) {
                warn "Not connected yet?";
                return;
            }
            my $res_cb = sub {}; # XXX
            # XXX also could do a huge list in eone slump
            for my $feed (@$list) {
                my $enc_feed = $feed; # XXX
                my $xmpp_uri = "xmpp:$SERVICE?;node=$enc_feed";
                $pubsub->subscribe_node($con, $xmpp_uri, $res_cb);
            }
        };
        $superfeedr->{sub_timer} = AnyEvent->timer(
            after => $iv, interval => $iv, cb => $timer_cb,
        );
    }
    my $cl   = AnyEvent::XMPP::Client->new(
        debug => $superfeedr->{debug},
    );
    my $pass = $superfeedr->{password};
    my $jid  = $superfeedr->{jid}
        or croak "You need to specify your jid";

    $cl->add_account($jid, $pass, undef, undef, {
        dont_retrieve_roster => 1,
    });
    $cl->add_extension(my $ps = AnyEvent::XMPP::Ext::Superfeedr->new);
    $superfeedr->{xmpp_pubsub} = $ps;

    my $on_error = $filtered{on_error} || sub {
        croak "Error: ". $_[2]->string;
    };

    $cl->reg_cb(
        error => $on_error, 
        connected => sub {
            $superfeedr->{xmpp_client} = $cl;
        },
        disconnect => sub {
            my ($account, $host, $port) = @_;
            warn "Got Disconnected from $host:$port\n";
        },
        connect_error => sub {
            my ($account, $reason) = @_;
            my $jid = $account->bare_jid;
            croak "connection error for $jid: $reason";
        },
    );
    if (my $on_notification = $filtered{on_notification} ) {
        $ps->reg_cb(
            superfeedr_notification => sub {
                my $ps = shift;
                my $notification = shift;
                $on_notification->($notification);
            },
        );
    }
    $cl->start;

    return $superfeedr;
}

sub xmpp_pubsub {
    my $superfeedr = shift;
    return $superfeedr->{xmpp_pubsub};
}

sub xmpp_connection {
    my $superfeedr = shift;
    my $con = $superfeedr->{xmpp_connection};
    return $con if $con;

    my $client = $superfeedr->{xmpp_client} or return;
    my $jid = $superfeedr->{jid};
    my $account = $client->get_account($jid) or return;
    $con = $account->connection;
    $superfeedr->{xmpp_connection} = $con;
    return $con;
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

AnyEvent::Superfeedr - XMPP interface to Superfeedr service.

=head1 SYNOPSIS

  use AnyEvent::Superfeedr;

  $end = AnyEvent->condvar;

  ## receive 20 notifications and stop
  $n = 0;
  $callback = sub {
      my Net::Superfeedr::Notification $notification = shift;
      my $feed_uri    = $notification->feed_uri;
      my $http_status = $notification->http_status;
      my $next_fetch  = $notification->next_fetch;
      printf "status %s for %s. next: %s\n",
              $http_status, $feed_uri, $next_fetch;
      for my XML::Atom::Entry $entry ($notification->entries) {
          printf "Got: %s\n" $entry->title;
      }
      $end->send if ++$n == 20;
  };

  $superfeedr = AnyEvent::Superfeedr->new(
      jid => $jid,
      password => $password
      subscription => {
          interval => 5,
          cb       => \%get_new_feeds,
      },
      on_notification => $callback,
  );

  $end->recv;

=head1 DESCRIPTION

Allows you to subscribe to feeds and get notified real-time about new
content.

This is a first version of the api, and probably only covers specific
architectural needs.

=head1 AUTHOR

Yann Kerherve E<lt>yannk@cpan.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<AnyEvent::XMPP> L<AnyEvent> L<http://superfeedr.com>

=cut
