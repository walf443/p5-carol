use strict;
use warnings;
use Test::TCP;
use Test::More;
use AnyEvent;
use AnyEvent::HTTP;
use AnyEvent::IRC::Server;
use AnyEvent::IRC::Client;
use AnyEvent::IRC::Util;
use Carol::IRCGateway::Wassr;
use Test::Mock::Guard;

my $server = Test::TCP->new(
    code => sub {
        my $port = shift;

        my $mock = Test::Mock::Guard::mock_guard('AnyEvent::HTTP', + {
            http_request => sub {
                my $cb = pop;
                my ($method, $url, %args) = @_;
                my $content = <<EOF;
[{
  "favorites": ["sample_id3", "sample_id2"],
  "user_login_id": "sample_id",
  "photo_thumbnail_url": "http://wassr.jp/user/sample_id/statuses/XXXXXXXXXX/photo_thumbnail",
  "html": "test",
  "text": "\@sample_id もどうぞよろしく",
  "reply_status_url" :"http://wassr.jp/user/sample_id/statuses/YYYYYYYYYY",
  "user":{
    "profile_image_url":"http://wassr.jp/user/sample_id/profile_img.png.64.1246432820",
    "protected":false,
    "screen_name":"sample_id"
  },
  "id":"696410",
  "reply_user_login_id":"sample_id",
  "link":"http://wassr.jp/user/staff/statuses/XXXXXXXXXX",
  "epoch":1251857805,
  "rid":"XXXXXXXXXX",
  "photo_url":"http://wassr.jp/user/sample_id/statuses/XXXXXXXXXX/photo",
  "reply_message":"ワッサーをどうぞよろしく",
  "reply_user_nick":"sample_id",
  "slurl":null,
  "areaname":null,
  "areacode": null
}]
EOF
                $cb->($content,{ 
                    Status => 200,
                });
            },
        });
        my $cv = AnyEvent->condvar;
        my $irc_server = AnyEvent::IRC::Server->new(port => $port);
        $irc_server->run;

        my $wig = Carol::IRCGateway::Wassr->new(
            server => $irc_server,
            account => +{},
        );

        my $guard_wig_public = $wig->start_public_timeline(channel => "#wig_public", interval => 1);

        $cv->wait;
    },
);

my $cv = AnyEvent->condvar;

my $client = AnyEvent::IRC::Client->new;
$client->reg_cb(connect => sub {
    my ($con, $err) = @_;
    if ( defined $err ) {
        warn "Can't connect to server: $err";
        return;
    }
    ok 1, 'connect ok';
});

$client->reg_cb(registered => sub {
    my ($self, ) = @_;
    ok 1, 'registered ok';
    $self->send_srv(JOIN => "#wig_public");
});

$client->reg_cb(privatemsg => sub {
    use Data::Dumper;
    warn Dumper(@_);
});

$client->reg_cb(channel_add => sub {
    my ($self, $msg, $channel, $nick, ) = @_;
    is($channel, "#wig_public", "join channel ok");
    is($nick, "client", "nick ok");
});

if ($ENV{DEBUG} ) {
    $client->reg_cb(debug_recv => sub {
        my ($self, $ircmsg) = @_;
        use Data::Dumper;
        warn Dumper($ircmsg);
    });
}

$client->connect("localhost", $server->port, { nick => "client" });

my $timer;
$timer = AnyEvent->timer(
    after => 10,
    cb  => sub {
        undef $timer;
        $cv->send;
    }
);

$cv->recv;

undef $server;

done_testing;
