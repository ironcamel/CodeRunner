package CodeRunner::Schema::Result::Attempt;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

CodeRunner::Schema::Result::Attempt

=cut

__PACKAGE__->table("attempt");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 user_id

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 100

=head2 problem

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 100

=head2 time_of

  data_type: 'date'
  is_nullable: 0

=head2 is_success

  data_type: 'int'
  is_nullable: 0

=head2 reason

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "user_id",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 100 },
  "problem",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 100 },
  "time_of",
  { data_type => "date", is_nullable => 0 },
  "is_success",
  { data_type => "int", is_nullable => 0 },
  "reason",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 problem

Type: belongs_to

Related object: L<CodeRunner::Schema::Result::Problem>

=cut

__PACKAGE__->belongs_to(
  "problem",
  "CodeRunner::Schema::Result::Problem",
  { name => "problem" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 user

Type: belongs_to

Related object: L<CodeRunner::Schema::Result::User>

=cut

__PACKAGE__->belongs_to(
  "user",
  "CodeRunner::Schema::Result::User",
  { id => "user_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2011-11-12 09:11:07
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:01bVlSOA9bJYSReg2+iskg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
