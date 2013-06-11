on configure => sub {
    requires 'Module::Build' => '0.4004';
    requires 'Module::CPANfile';
    requires 'autodie';
    requires 'encoding::warnings';
    requires 'warnings';
};

requires 'Carp';
requires 'Data::Dumper';
requires 'Encode';
requires 'English';
requires 'Filter::Simple';
requires 'HTTP::Status';
requires 'Module::Load';
requires 'Module::Pluggable::Object';
requires 'Plack::Component';
requires 'Plack::Request';
requires 'Plack::Response';
requires 'Plack::Util::Accessor';
requires 'parent';
requires 're' => '0.18';
requires 'sort';
requires 'version';
recommends 'Smart::Comments';
recommends 'Text::Table::Tiny';
suggests 'Time::Piece';

on test => sub {
    requires 'B::Deparse';
    requires 'FindBin';
    requires 'HTTP::Request::Common';
    requires 'JSON::PP';
    requires 'Module::Loaded';
    requires 'Plack::Test';
    requires 'Test::More';
    requires 'bytes';
    requires 'utf8';
    suggests 'Template';
};
