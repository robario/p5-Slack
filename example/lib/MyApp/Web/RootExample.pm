package MyApp::Web::RootExample;
use Slack qw(Controller);

# prefix was '/rootexample', it is changed to '/'
sub prefix { '/' }

action index => '' => sub {
    res->body('RootExample index action');
};

action default => qr{.+} => sub {
    res->body('RootExample default action');
};

1;
