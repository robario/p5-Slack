package MyApp::Web::Hello;
use Slack qw(Controller);

# /hello/
action index => '' => sub {
    res->body('hello');
};

# /hello/world
action world => sub {
    res->body('hello, world');
};

# /hello/[^/]+\z
action name => qr{(?<name>[^/]+)\z} => sub {
    res->body( 'hello, ' . req->args->{name} );
};

# /hello/ng
action 'next-generation' => 'ng' => sub {
    res->stash->{greeting} = 'hello, world';
};

1;
