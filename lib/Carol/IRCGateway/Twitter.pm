package Carol::IRCGateway::Twitter;

use strict;
use warnings;
use Carol::DummyHandle;
use Class::Accessor::Lite (
    new => 1,
    ro => [qw( server account channel interval )],
);
use AnyEvent;
use AnyEvent::Twitter::Stream;
use AnyEvent::HTTP;
use Log::Minimal qw(debugf infof warnf critf );
use Cache::LRU;
use MIME::Base64;
use JSON::XS;
use Encode;
use Smart::Args;
use HTML::Entities qw();

sub start {
    args my $self,
        my $channel => 'Str';

    my $publish_privmsg = $self->publish_privmsg(channel => $channel);
    my $listener = AnyEvent::Twitter::Stream->new(
        consumer_key => $self->account->{consumer_key},
        consumer_secret => $self->account->{consumer_secret},
        token           => $self->account->{token},
        token_secret    => $self->account->{token_secret},
        method => "userstream",
        no_decode_json => 1,
        on_tweet => sub {
            my $tweet = shift;
            use Data::Dumper;
            my $json;
            if ( $tweet =~ /^{/ ) {
                eval {
                    $json = JSON::XS->new->utf8->decode($tweet);
                };
            }
            if ( $@ ) {
                critf("Can't parse json: $@");
            } else {
                if ( $json ) {
                    $publish_privmsg->($json);
                }
            }
        },
    );

    return $listener;
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
        if ( $cache->get($status->{id}) ) {
        } else {
            my $timer;
            $timer = AnyEvent->timer(
                after => 1.0,
                cb  => sub {
                    undef $timer;
                    my $dummy_handle = Carol::DummyHandle->new(
                        nick => $status->{user}->{screen_name}, 
                        user => $status->{user}->{screen_name},
                        servername => "tig"
                    );
                    if ( $status->{user_login_id} && $status->{user_login_id} ne $self->account->{login_id} ) {
                        $server->event(
                            join => +{
                                params => [
                                    "$channel,",
                                ],
                            },
                            $dummy_handle,
                        );
                    }
                    my $message = $self->status2irc_message($status);
                    if ( $message ) {
                        $server->daemon_cmd_privmsg($status->{user}->{screen_name}, $channel, $message);
                        debugf(sprintf("send privmsg: %s %s", $status->{user}->{screen_name}, $status->{text}));
                    }
                },
            );
            $cache->set($status->{id} => 1);
        }
    };
}

sub request_twitter {
    my $self = shift;
    my $method = shift;
    my $path = shift;
    my $cb = pop;
    my %args = @_;

    my $ua = AnyEvent::Twitter->new(
        consumer_key => $self->{account}->{consumer_key},
        consumer_secret => $self->{account}->{consumer_secret},
        access_token    => $self->{account}->{access_token},
        access_token_secret    => $self->{account}->{access_token_secret},
    );
    $ua->request(
        method => $method,
        api    => $path,
    );
}

sub status2irc_message {
    my ($self, $status) = @_;

    my $msg = "";
    $msg .= $status->{text};
    return Encode::encode_utf8(HTML::Entities::decode_entities($msg));
}

1;

__END__

=head1 NAME

Carol -

=head1 SYNOPSIS

  use AnyEvent;
  use AnyEvent::IRC::Server;
  use Carol::IRCGateway::Twitter;
  my $cv = AnyEvent->condvar;
  my $server = AnyEvent::IRC::Server->new(port => 16667);
  $server->run;
  my $tig = Carol::IRCGateway::Twitter->new(
      server => $server
      account => +{
        login_id => 'user',
        password => '',
      },
  );
  my $tig_guard = $tig->start(channel => "#tig", interval => 20.0);
  $cv->wait;
  undef $tig_guard;

=head1 DESCRIPTION

Carol is

=head1 AUTHOR

Keiji Yoshimi E<lt>walf443 at gmail dot comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
