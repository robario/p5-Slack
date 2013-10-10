requires 'encoding::warnings';
requires 'parent';
requires 'perl' => 'v5.14.0';
requires 're' => '0.18';
requires 'sort';
requires 'version' => '0.77';
requires 'warnings';
requires 'Carp';
requires 'Class::Struct';
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
recommends 'Smart::Comments';
recommends 'Text::Table::Tiny';

on configure => sub {
    requires 'autodie';
    requires 'Module::Build';
};

on test => sub {
    requires 'bytes';
    requires 'utf8';
    requires 'B::Deparse';
    requires 'FindBin';
    requires 'HTTP::Request::Common';
    requires 'JSON::PP';
    requires 'Module::Loaded';
    requires 'Plack::Test';
    requires 'Test::More';
    recommends 'Template';
};

on develop => sub {
    requires 'File::Find';
    recommends 'Devel::SawAmpersand';
    recommends 'Test::Perl::Critic';
};
