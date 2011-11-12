package CodeRunner::Schema::Result::Problem;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

CodeRunner::Schema::Result::Problem

=cut

__PACKAGE__->table("problem");

=head1 ACCESSORS

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=cut

__PACKAGE__->add_columns(
  "name",
  { data_type => "varchar", is_nullable => 0, size => 100 },
);
__PACKAGE__->set_primary_key("name");

=head1 RELATIONS

=head2 attempts

Type: has_many

Related object: L<CodeRunner::Schema::Result::Attempt>

=cut

__PACKAGE__->has_many(
  "attempts",
  "CodeRunner::Schema::Result::Attempt",
  { "foreign.problem" => "self.name" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2011-11-12 09:11:07
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:A9qGAGwVj+Fe5Mcl008GpQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
