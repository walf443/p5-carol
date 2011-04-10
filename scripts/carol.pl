#!perl
use strict;
use warnings;
use AnyEvent::IRC::Server;
use Carol::IRCGateway::Wassr;
use opts;
use Filesys::Notify::Simple;
use Config::Pit qw();

main(@ARGV); exit;

sub main {
    opts 
        my $port => +{ isa => 'Int', default => 16667, comment => "server port" },
        my $reload => +{ isa => 'Bool', default => 0, comment => "restart when some files changed" };

    if ( $reload ) {
        while ( 1 ) {
            my $pid = fork();
            die "Can't fork: $!" unless defined $pid;
            if ( $pid ) {
                my $watcher = Filesys::Notify::Simple->new(["."]);
                $watcher->wait(sub {
                    kill $pid;
                });
            } else {
                run_irc_server($port);
                exit;
            }
        }
    } else {
        run_irc_server($port);
    }
}

sub run_irc_server {
    my $port = shift;

    local $SIG{TERM} = sub {
        exit;
    };
    my $cv = AnyEvent->condvar;
    my $server = AnyEvent::IRC::Server->new(port => $port);
    $server->run;

    my $wig = Carol::IRCGateway::Wassr->new(
        server => $server,
        account => Config::Pit::pit_get("wassr.jp", require => {
            "login_id" => "your login_id",
            "password" => "your password",
        }),
        interval => 10.0,
    );
    my $wig_public_guard = $wig->start_public_timeline(
        channel => "#wig_public",
        interval => 10.0,
    );
    my $wig_friends_guard = $wig->start_friends_timeline(
        channel => "#wig",
        interval => 10.0,
    );
    $cv->wait;
    undef $wig_public_guard;
    undef $wig_friends_guard;
}

