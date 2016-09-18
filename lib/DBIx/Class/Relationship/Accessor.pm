package # hide from PAUSE
    DBIx::Class::Relationship::Accessor;

use strict;
use warnings;
use DBIx::Class::Carp;
use DBIx::Class::_Util qw(quote_sub perlstring);
use namespace::clean;

our %_pod_inherit_config =
  (
   class_map => { 'DBIx::Class::Relationship::Accessor' => 'DBIx::Class::Relationship' }
  );

sub register_relationship {
  my ($class, $rel, $info) = @_;
  if (my $acc_type = $info->{attrs}{accessor}) {
    $class->add_relationship_accessor($rel => $acc_type);
  }
  $class->next::method($rel => $info);
}

sub add_relationship_accessor {
  my ($class, $rel, $acc_type) = @_;

  if ($acc_type eq 'single') {

    my @qsub_args = ( {}, {
      attributes => [qw(
        DBIC_method_is_single_relationship_accessor
        DBIC_method_is_generated_from_resultsource_metadata
      )]
    });


    quote_sub "${class}::${rel}" => sprintf(<<'EOC', perlstring $rel), @qsub_args;
      my $self = shift;

      if (@_) {
        $self->set_from_related( %1$s => @_ );
        return $self->{_relationship_data}{%1$s} = $_[0];
      }
      elsif (exists $self->{_relationship_data}{%1$s}) {
        return $self->{_relationship_data}{%1$s};
      }
      else {
        my $rsrc = $self->result_source;

        my $jfc;

        return undef if (

          $rsrc->relationship_info(%1$s)->{attrs}{undef_on_null_fk}

            and

          $jfc = ( $rsrc->_resolve_relationship_condition(
            rel_name => %1$s,
            foreign_alias => %1$s,
            self_alias => 'me',
            self_result_object => $self,
          )->{join_free_condition} || {} )

            and

          grep { not defined $_ } values %%$jfc
        );

        my $val = $self->related_resultset( %1$s )->single;
        return $val unless $val;  # $val instead of undef so that null-objects can go through

        return $self->{_relationship_data}{%1$s} = $val;
      }
EOC
  }
  elsif ($acc_type eq 'filter') {

    my $rsrc = $class->result_source_instance;

    $rsrc->throw_exception("No such column '$rel' to filter")
       unless $rsrc->has_column($rel);

    my $f_class = $rsrc->relationship_info($rel)->{class};

    $class->inflate_column($rel, {
      inflate => sub {
        my ($val, $self) = @_;
        return $self->find_or_new_related($rel, {});
      },
      deflate => sub {
        my ($val, $self) = @_;
        $self->throw_exception("'$val' isn't a $f_class") unless $val->isa($f_class);

        # MASSIVE FIXME - this code assumes we pointed at the PK, but the belongs_to
        # helper does not check any of this
        # fixup the code a bit to make things saner, but ideally 'filter' needs to
        # be deprecated ASAP and removed shortly after
        # Not doing so before 0.08250 however, too many things in motion already
        my ($pk_col, @rest) = $val->result_source->_pri_cols_or_die;
        $self->throw_exception(
          "Relationship '$rel' of type 'filter' can not work with a multicolumn primary key on source '$f_class'"
        ) if @rest;

        my $pk_val = $val->get_column($pk_col);
        carp_unique (
          "Unable to deflate 'filter'-type relationship '$rel' (related object "
        . "primary key not retrieved), assuming undef instead"
        ) if ( ! defined $pk_val and $val->in_storage );

        return $pk_val;
      },
    });


    # god this is horrible...
    my $acc =
      $rsrc->columns_info->{$rel}{accessor}
        ||
      $rel
    ;

    # because CDBI may elect to never make an accessor at all...
    if( my $main_cref = $class->can($acc) ) {

      attributes->import(
        $class,
        $main_cref,
        qw(
          DBIC_method_is_filter_relationship_accessor
          DBIC_method_is_generated_from_resultsource_metadata
        ),
      );

      if( my $extra_cref = $class->can("_${acc}_accessor") ) {
        attributes->import(
          $class,
          $extra_cref,
          qw(
            DBIC_method_is_filter_relationship_extra_accessor
            DBIC_method_is_generated_from_resultsource_metadata
          ),
        );
      }
    }
  }
  elsif ($acc_type eq 'multi') {


    my @qsub_args = (
      {},
      {
        attributes => [qw(
          DBIC_method_is_multi_relationship_accessor
          DBIC_method_is_generated_from_resultsource_metadata
          DBIC_method_is_indirect_sugar
        )]
      },
    );


    quote_sub "${class}::${rel}", sprintf( <<'EOC', perlstring $rel ), @qsub_args;
      DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and DBIx::Class::_Util::fail_on_internal_call;
      DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_WANTARRAY and my $sog = DBIx::Class::_Util::fail_on_internal_wantarray;
      shift->related_resultset(%s)->search( @_ )
EOC


    $qsub_args[1]{attributes}[0]
      =~ s/^DBIC_method_is_multi_relationship_accessor$/DBIC_method_is_multi_relationship_extra_accessor/
    or die "Unexpected attr '$qsub_args[1]{attributes}[0]' ...";


    quote_sub "${class}::${rel}_rs", sprintf( <<'EOC', perlstring $rel ), @qsub_args;
      DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and DBIx::Class::_Util::fail_on_internal_call;
      shift->related_resultset(%s)->search_rs( @_ )
EOC


    quote_sub "${class}::add_to_${rel}", sprintf( <<'EOC', perlstring $rel ), @qsub_args;
      DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and DBIx::Class::_Util::fail_on_internal_call;
      shift->create_related( %s => @_ );
EOC

  }
  else {
    $class->throw_exception("No such relationship accessor type '$acc_type'");
  }

}

1;
