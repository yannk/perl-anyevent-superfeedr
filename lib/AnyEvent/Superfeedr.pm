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
use URI::Escape();

use constant DEFAULT_SUB_IV => 60;

our $SERVICE = 'firehoser.superfeedr.com';

# TODO:
# debug
# tests? worthwhile?
#
# Also, maybe more direct callbacks for sub/unsub

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

    my $on_error = $filtered{on_error} || sub {
        my $err = shift;
        warn "Error: " . $err->string;
    };

    if (my $s = $filtered{subscription}) {
        my $sub_cb = $s->{sub_cb}
            or croak "subscription needs to pass a 'sub_cb' callback";
        my $iv = $s->{interval} || DEFAULT_SUB_IV;
        my $unsub_cb = $s->{unsub_cb};

        my $timer_sub_cb = sub {
            my $list = $sub_cb->($superfeedr);
            return unless $list && @$list;
            my $pubsub = $superfeedr->xmpp_pubsub;
            my $con    = $superfeedr->xmpp_connection;
            unless ($pubsub && $con) {
                warn "Not connected yet?";
                return;
            }
            # XXX also could do a huge list in one slump
            for my $feed (@$list) {
                $superfeedr->subscribe($feed);
            }
        };
        $superfeedr->{sub_timer} = AnyEvent->timer(
            after => $iv, interval => $iv, cb => $timer_sub_cb,
        );

        if ($unsub_cb) {
            my $timer_unsub_cb = sub {
                my $list = $unsub_cb->($superfeedr);
                return unless $list && @$list;
                my $pubsub = $superfeedr->xmpp_pubsub;
                my $con    = $superfeedr->xmpp_connection;
                unless ($pubsub && $con) {
                    warn "Not connected yet?";
                    return;
                }
                # XXX also could do a huge list in one slump
                for my $feed (@$list) {
                    $superfeedr->unsubscribe($feed);
                }
            };
            $superfeedr->{unsub_timer} = AnyEvent->timer(
                after => $iv, interval => $iv, cb => $timer_unsub_cb,
            );
        }
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
            $on_error->("connection error for $jid: $reason");
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

sub subscribe {
    my $superfeedr = shift;
    my ($feed_uri) = @_;
    my $pubsub = $superfeedr->xmpp_pubsub;
    unless ($pubsub) {
        $superfeedr->event(error => "no pubsub extension available");
        return;
    }
    my $con = $superfeedr->xmpp_connection;
    unless ($con) {
        $superfeedr->event(error => "Wait to be connected");
        return;
    }
    my $res_cb = sub {
        my $err = shift;
        $superfeedr->event(error => $err) if $err;
    };
    my $xmpp_uri = xmpp_node_uri($feed_uri);
    $pubsub->subscribe_node($con, $xmpp_uri, $res_cb);
    return;
}

sub unsubscribe {
    my $superfeedr = shift;
    my ($feed_uri) = @_;
    my $pubsub = $superfeedr->xmpp_pubsub;
    unless ($pubsub) {
        $superfeedr->event(error => "no pubsub extension available");
        return;
    }
    my $con = $superfeedr->xmpp_connection;
    unless ($con) {
        $superfeedr->event(error => "Wait to be connected");
        return;
    }
    my $res_cb = sub {
        my $err = shift;
        $superfeedr->event(error => $err) if $err;
    };
    my $xmpp_uri = xmpp_node_uri($feed_uri);
    $pubsub->unsubscribe_node($con, $xmpp_uri, $res_cb);
    return;
}

sub xmpp_node_uri {
    my $enc_feed = URI::Escape::uri_escape_utf8(shift, "\x00-\x1f\x7f-\xff");
    # work around what I think is a but in AnyEvent::XMPP
    #return "xmpp:$SERVICE?;node=$enc_feed";
    return "xmpp:$SERVICE?sub;node=$enc_feed";
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
          sub_cb   => \%get_new_feeds,
          unsub_cb => \%get_feeds2delete,
      },
      on_notification => $callback,
  );

  $superfeedr->subscribe($feed_uri);
  $superfeedr->unsubscribe($feed_uri);

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
