requires 'encoding::warnings';
requires 'parent';
requires 'perl' => 'v5.14.0';
requires 're'   => '0.18';
requires 'sort';
requires 'warnings';
requires 'Class::Struct';
requires 'Encode';
requires 'English';
requires 'HTTP::Status';
requires 'Module::Load';
requires 'Module::Pluggable::Object';
requires 'Plack::Component';
requires 'Plack::Request';
requires 'Plack::Response';
requires 'Plack::Util::Accessor';
recommends 'Data::Dumper';
recommends 'Smart::Comments';
recommends 'Text::Table::Tiny';

on configure => sub {
    requires 'autodie';
    requires 'Module::Build' => '>= 0.3800, != 0.4200';
};

on test => sub {
    requires 'bytes';
    requires 'utf8';
    requires 'Carp';
    requires 'FindBin';
    requires 'HTTP::Request::Common';
    requires 'JSON::PP';
    requires 'Module::Loaded';
    requires 'Plack::Test';
    requires 'Test::More';
    requires 'Test::Warnings';
};

on develop => sub {
    requires 'CPAN::Meta::Requirements';
    requires 'File::Find';
    recommends 'Devel::SawAmpersand';
    recommends 'Test::Perl::Critic';
    recommends 'Test::Pod';
    recommends 'Test::Strict';
};
