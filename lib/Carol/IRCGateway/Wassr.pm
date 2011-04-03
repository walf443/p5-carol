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
use JSON::XS;
use Encode;
use Smart::Args;

sub start_public_timeline {
    args my $self,
        my $channel => 'Str',
        my $interval => 'Int';

    my $server = $self->server;
    my $publish_privmsg = $self->publish_privmsg(channel => $channel);
    my $timer = AnyEvent->timer(
        after => 1,
        interval => $interval,
        cb => sub {
            http_get 'http://api.wassr.jp/statuses/public_timeline.json', sub {
                my ($content,  $meta) = @_;

                if ( $meta->{Status} == 200 ) {
                    infof("got data from public_timeline");
                    my $json = JSON::XS->new->utf8->decode($content);
                    for my $status ( @{ $json } ) {
                        $publish_privmsg->($status);
                    }
                } else {
                    warnf("got error while fetching public_timeline");
                }
            };
        }
    );

    return $timer;
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
                    $server->event(
                        join => +{
                            params => [
                                "$channel,",
                            ],
                        },
                        $dummy_handle,
                    );
                    $server->daemon_cmd_privmsg($status->{user_login_id}, $channel, $self->status2irc_message($status));
                    debugf(sprintf("send privmsg: %s %s", $status->{user_login_id}, $status->{text}));
                },
            );
            $cache->set($status->{rid} => 1);
        }
    };
}

sub status2irc_message {
    my ($self, $status) = @_;

    my $msg = "";
    $msg .= $status->{text};
    return Encode::encode_utf8($msg);
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
