package Carol::DummyHandle;
use strict;
use warnings;

sub new {
    my $class = shift;

    bless {
        nick => '',
        @_,
    }, $class;

}

sub push_write {}

1;

