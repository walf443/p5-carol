package Carol::DummyHandle;
sub new {
    my $class = shift;

    bless {
        nick => '',
        @_,
    }, $class;

}

sub push_write {}

1;

