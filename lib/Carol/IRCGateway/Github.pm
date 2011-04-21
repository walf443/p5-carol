package Carol::IRCGateway::Github;

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
use XML::Feed;
use Encode;
use Smart::Args;

sub start {
    args my $self,
        my $channel => 'Str',
        my $interval => 'Int';

    my $server = $self->server;
    my $publish_privmsg = $self->publish_privmsg(channel => $channel);
    my $timer = AnyEvent->timer(
        after => 1,
        interval => $interval,
        cb => sub {
            $self->request_github(GET => $self->account->{login_id} . '.private.atom?token=' . $self->account->{password}, authorize => 1, sub {
                my ($feed, $meta) = @_;
                for my $entry ( $feed->entries ) {
                    $publish_privmsg->($entry);
                }
            });
        },
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
        if ( $cache->get($status->id) ) {
        } else {
            my $timer;
            $timer = AnyEvent->timer(
                after => 1.0,
                cb  => sub {
                    undef $timer;
                    my $dummy_handle = Carol::DummyHandle->new(
                        nick => $status->author, 
                        user => $status->author,
                        servername => "gig"
                    );
                    $server->event(
                        join => +{
                            params => [
                                "$channel,",
                            ],
                        },
                        $dummy_handle,
                    );
                    $server->daemon_cmd_privmsg($status->author, $channel, $self->status2irc_message($status));
                    debugf(sprintf("send privmsg: %s %s", $status->author, $status->title));
                },
            );
            $cache->set($status->id => 1);
        }
    };
}

sub request_github {
    my $self = shift;
    my $method = shift;
    my $path = shift;
    my $cb = pop;
    my %args = @_;

    my $url = "https://github.com/" . $path;

    AnyEvent::HTTP::http_request($method, $url, %args, sub {
        my ($content,  $meta) = @_;

        $path =~ s/token=([^&]+)/token=****/g; # don't show pass to log.
        if ( $meta->{Status} == 200 ) {
            debugf("fetch data from $path");
            my $feed;
            $content =~ s{<content [^>]*>[^<]*?</content>}{}smg; # どうもPCDATAを入れてないかんけいでパーサがこけるよう
            eval {
                $feed = XML::Feed->parse(\$content, "Atom")
                    or die XML::Feed->errstr;
            };
            if ( $@ ) {
                critf("Can't parse feed: $@");
            }
            if ( $feed ) {
                $cb->($feed, $meta);
            }
        } else {
            warnf("got error @{[ $meta->{Status} ]} while fetching $path");
        }
    });
}

sub status2irc_message {
    my ($self, $status) = @_;

    my $msg = "";
    $msg .= $status->title;
    $msg =~ s/\b@{[ $status->author ]}\s//; # remove duplicate info
    $msg .= " " . $status->link;
    return Encode::encode_utf8($msg);
}

1;

__END__

=head1 NAME

Carol -

=head1 SYNOPSIS

  use AnyEvent;
  use AnyEvent::IRC::Server;
  use Carol::IRCGateway::Github;
  my $cv = AnyEvent->condvar;
  my $server = AnyEvent::IRC::Server->new(port => 16667);
  $server->run;
  my $gig = Carol::IRCGateway::Github->new(
      server => $server
      account => +{
        login_id => 'user',
        password => '',
      },
  );
  my $gig_guard = $wig->start(channel => "#wig_public", interval => 30.0);
  $cv->wait;
  undef $gig_guard;

=head1 DESCRIPTION

Carol is

=head1 AUTHOR

Keiji Yoshimi E<lt>walf443 at gmail dot comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
