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

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 title

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 description

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 input_desc

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 output_desc

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 sample_input

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 sample_output

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 input

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 output

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "title",
  { data_type => "varchar", is_nullable => 0, size => 100 },
  "description",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "input_desc",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "output_desc",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "sample_input",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "sample_output",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "input",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "output",
  { data_type => "text", default_value => "", is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("title_unique", ["title"]);

=head1 RELATIONS

=head2 attempts

Type: has_many

Related object: L<CodeRunner::Schema::Result::Attempt>

=cut

__PACKAGE__->has_many(
  "attempts",
  "CodeRunner::Schema::Result::Attempt",
  { "foreign.problem" => "self.title" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2011-12-02 19:11:13
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:iO7eRoSxyMBnZs5TQmv9IQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration

__PACKAGE__->has_many(
  "attempts",
  "CodeRunner::Schema::Result::Attempt",
  { "foreign.problem" => "self.title" },
  { cascade_copy => 0, cascade_delete => 1 },
);

1;
