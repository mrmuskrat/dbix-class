package DBICTest::Schema::EventTZDeprecated;

use strict;
use warnings;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->load_components(qw/InflateColumn::DateTime/);

__PACKAGE__->table('event');

__PACKAGE__->add_columns(
  id => { data_type => 'integer', is_auto_increment => 1 },
  starts_at => { data_type => 'datetime', extra => { time_zone => "America/Chicago", locale => 'de_DE' } },

  # DO NOT change 'timezone' - there to test the legacy syntax
  created_on => { data_type => 'timestamp', extra => { timezone => "America/Chicago", floating_tz_ok => 1 } },
);

__PACKAGE__->set_primary_key('id');

sub _datetime_parser {
  require DateTime::Format::MySQL;
  DateTime::Format::MySQL->new();
}


1;
