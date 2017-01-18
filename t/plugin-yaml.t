use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use File::Spec::Functions;
use Mojolicious;
use lib '.';
use t::Api;

plan skip_all => "Fails with JSON::Validator 0.91" unless $ENV{TEST_EVERYTHING};

my $n = 0;

#
# This test checks that "require: false" is indeed false
# https://github.com/jhthorsen/swagger2/issues/39
#

for my $module (qw( YAML::XS YAML::Syck )) {
  unless (eval "require $module;1") {
    diag "Skipping test when $module is not installed";
    next;
  }

  no warnings 'once';
  local *Swagger2::LoadYAML = eval "\\\&$module\::Load";
  $n++;

  diag join ' ', $module, $module->VERSION || 0;

  my $app = Mojolicious->new;
  unless (eval { $app->plugin(Swagger2 => {url => 't/data/petstore.yaml'}); 1 }) {
    diag $@;
    ok 0, "Could not load Swagger2 plugin using $module";
    next;
  }

  my $t = Test::Mojo->new($app);

  $t::Api::RES = [{id => 123, name => "kit-cat"}];
  $t->get_ok('/v1/pets')->status_is(200)->json_is('/0/id', 123)->json_is('/0/name', 'kit-cat');
}

ok 1, 'no yaml modules available' unless $n;

done_testing;
