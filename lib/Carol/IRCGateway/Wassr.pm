package Carol::IRCGateway::Wassr;

use strict;
use warnings;
use Carol::DummyHandle;
use Class::Accessor::Lite (
    new => 1,
    ro => [qw( server account channel interval )],
);
use AnyEvent;
use AnyEvent::HTTP;
use Log::Minimal qw(debugf infof warnf critf );
use Cache::LRU;
use MIME::Base64;
use JSON::XS;
use Encode;
use URI::Escape;
use HTML::Entities qw();
use Smart::Args;

sub start_public_timeline {
    args my $self,
        my $channel => 'Str',
        my $interval => 'Int';

    my $server = $self->server;
    $self->register_post_wassr($channel);
    my $publish_privmsg = $self->publish_privmsg(channel => $channel);
    my $timer = AnyEvent->timer(
        after => 1,
        interval => $interval,
        cb => sub {
            $self->request_wassr(GET => '/statuses/public_timeline.json', sub {
                my ($json, $meta) = @_;
                for my $status ( @{ $json } ) {
                    $publish_privmsg->($status);
                }
            });
        },
    );

    return $timer;
}

sub start_friends_timeline {
    args my $self,
        my $channel => 'Str',
        my $interval => 'Int';

    my $server = $self->server;
    my $publish_privmsg = $self->publish_privmsg(channel => $channel);
    $self->register_post_wassr($channel);
    my $timer = AnyEvent->timer(
        after => 1,
        interval => $interval,
        cb => sub {
            $self->request_wassr(GET => '/statuses/friends_timeline.json', 
                authorize => 1, 
                sub {
                my ($json, $meta) = @_;
                for my $status ( @{ $json } ) {
                    $publish_privmsg->($status);
                }
            });
        },
    );

    return $timer;
}

sub register_post_wassr {
    my ($self, $channel) = @_;

    $self->server->reg_cb(
        daemon_privmsg => sub {
            my ($irc, $nick, $chan, $text ) = @_;
            if ( $chan eq $channel ) {
                my $cv = AnyEvent->condvar;
                $cv->begin;
                $self->request_wassr(POST => '/statuses/update.json?source=carol_wig&status=' . URI::Escape::uri_escape($text) . '&id=' . $self->account->{login_id}, 
                    authorize => 1,
                    sub {
                        $cv->end;
                });
            }
        },
    );
}

sub publish_privmsg {
    args my $self,
        my $channel => "Str";

    my $cache = Cache::LRU->new(
        size => 100,
    );

    return sub {
        my ($status, ) = @_;

        my $server = $self->server;
        if ( $cache->get($status->{rid}) ) {
        } else {
            my $timer;
            $timer = AnyEvent->timer(
                after => 1.0,
                cb  => sub {
                    undef $timer;
                    my $dummy_handle = Carol::DummyHandle->new(
                        nick => $status->{user_login_id}, 
                        user => $status->{user_login_id},
                        servername => "wig"
                    );
                    if ( $status->{user_login_id} ne $self->account->{login_id} ) {
                        $server->event(
                            join => +{
                                params => [
                                    "$channel,",
                                ],
                            },
                            $dummy_handle,
                        );
                    }
                    $server->daemon_cmd_privmsg($status->{user_login_id}, $channel, $self->status2irc_message($status));
                    debugf(sprintf("send privmsg: %s %s", $status->{user_login_id}, $status->{text}));
                },
            );
            $cache->set($status->{rid} => 1);
        }
    };
}

sub request_wassr {
    my $self = shift;
    my $method = shift;
    my $path = shift;
    my $cb = pop;
    my %args = @_;

    my $url = "http://api.wassr.jp" . $path;
    my $authorize = delete $args{authorize};
    $args{headers} ||= {};
    $args{headers}->{'user-agent'} ||= "Carol";

    if ( $authorize ) {
        $args{headers}->{'Authorization'} = "Basic " . MIME::Base64::encode_base64(join ":", ($self->account->{login_id}, $self->account->{password}));
    }

    AnyEvent::HTTP::http_request($method, $url, %args, sub {
        my ($content,  $meta) = @_;

        if ( $meta->{Status} == 200 ) {
            debugf("fetch data from $path");
            my $json = JSON::XS->new->utf8->decode($content);
            $cb->($json, $meta);
        } else {
            warnf("got error @{[ $meta->{Status} ]} while fetching $path");
        }
    });
}

sub status2irc_message {
    my ($self, $status) = @_;

    my $msg = "";
    if ( my $reply_to = $status->{reply_user_login_id} ) {
        if ( $status->{text} !~ /^\@$reply_to/ ) {
            $msg .= "\@$reply_to ";
        }
    }
    $msg .= $status->{text};
    if ( $status->{areaname} ) {
        $msg .= " L: " . $status->{areaname};
    }
    if ( $status->{photo_url} ) {
        $msg .= " " . $status->{photo_url};
    }
    return Encode::encode_utf8(HTML::Entities::decode_entities($msg));
}

1;

__END__

=head1 NAME

Carol -

=head1 SYNOPSIS

  use AnyEvent;
  use AnyEvent::IRC::Server;
  use Carol::IRCGateway::Wassr;
  my $cv = AnyEvent->condvar;
  my $server = AnyEvent::IRC::Server->new(port => 16667);
  $server->run;
  my $wig = Carol::IRCGateway::Wassr->new(
      server => $server
      account => +{
        login_id => 'user',
        password => '',
      },
  );
  my $wig_guard = $wig->start_public_timeline(channel => "#wig_public", interval => 20.0);
  $cv->wait;
  undef $wig_guard;

=head1 DESCRIPTION

Carol is

=head1 AUTHOR

Keiji Yoshimi E<lt>walf443 at gmail dot comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
