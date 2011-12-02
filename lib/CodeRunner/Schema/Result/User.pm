package CodeRunner::Schema::Result::User;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

CodeRunner::Schema::Result::User

=cut

__PACKAGE__->table("user");

=head1 ACCESSORS

=head2 id

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 password

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 email

  data_type: 'varchar'
  is_nullable: 1
  size: 100

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "varchar", is_nullable => 0, size => 100 },
  "password",
  { data_type => "varchar", is_nullable => 0, size => 100 },
  "email",
  { data_type => "varchar", is_nullable => 1, size => 100 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 attempts

Type: has_many

Related object: L<CodeRunner::Schema::Result::Attempt>

=cut

__PACKAGE__->has_many(
  "attempts",
  "CodeRunner::Schema::Result::Attempt",
  { "foreign.user_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2011-12-02 18:48:16
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:eJddT1JSMzAjKXJ9FaUxMQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration

__PACKAGE__->has_many(
  "attempts",
  "CodeRunner::Schema::Result::Attempt",
  { "foreign.user_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 1 },
);

1;
