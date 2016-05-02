package Swagger2::SchemaValidator;
use Mojo::Base 'JSON::Validator';
use Scalar::Util ();

use constant DEBUG   => $ENV{SWAGGER2_DEBUG};
use constant IV_SIZE => eval 'require Config;$Config::Config{ivsize}';

our %COLLECTION_RE = (pipes => qr{\|}, csv => qr{,}, ssv => qr{\s}, tsv => qr{\t});

has json_validator => sub { JSON::Validator->new; };

sub coerce_by_collection_format {
  my ($self, $schema, $value) = @_;
  my $re = $COLLECTION_RE{$schema->{collectionFormat}} || '';
  my $type = $schema->{items}{type} || '';
  my @data;

  return [ref $value ? @$value : $value] unless $re;
  defined and push @data, split /$re/ for ref $value ? @$value : $value;
  return [map { $_ + 0 } @data] if $type eq 'integer' or $type eq 'number';
  return \@data;
}

sub is_true {
  return $_[0] if ref $_[0] and !Scalar::Util::blessed($_[0]);
  return 0 if !$_[0] or $_[0] =~ /^(n|false|off)/i;
  return 1;
}

sub validate_input {
  my $self = shift;
  local $self->{validate_input} = 1;
  $self->validate(@_);
}

sub validate_parameter {
  my ($self, $p, $name, $value) = @_;
  my $type = $p->{type} || 'object';
  my @e;

  return if !defined $value and !is_true($p->{required});

  my $in     = $p->{in};
  my $schema = {
    properties => {$name => $p->{'x-json-schema'} || $p->{schema} || $p},
    required => [$p->{required} ? ($name) : ()]
  };

  if ($in eq 'body') {
    warn "[Swagger2] Validate $in $name\n" if DEBUG;
    if ($p->{'x-json-schema'}) {
      return $self->json_validator->validate({$name => $value}, $schema);
    }
    else {
      return $self->validate_input({$name => $value}, $schema);
    }
  }
  elsif (defined $value) {
    warn "[Swagger2] Validate $in $name=$value\n" if DEBUG;
    return $self->validate_input({$name => $value}, $schema);
  }
  else {
    warn "[Swagger2] Validate $in $name=undef\n" if DEBUG;
    return $self->validate_input({$name => $value}, $schema);
  }

  return;
}

sub _validate_type_array {
  my ($self, $data, $path, $schema) = @_;

  if (  ref $data eq 'ARRAY'
    and ref $schema->{items} eq 'HASH'
    and $schema->{items}{collectionFormat})
  {
    $_ = $self->coerce_by_collection_format($schema->{items}, $_) for @$data;
  }

  return $self->SUPER::_validate_type_array(@_[1, 2, 3]);
}

# always valid
sub _validate_type_file { }

sub _validate_type_object {
  return shift->SUPER::_validate_type_object(@_) unless $_[0]->{validate_input};

  my ($self, $data, $path, $schema) = @_;
  my $properties = $schema->{properties} || {};
  my (%ro, @e);

  for my $p (keys %$properties) {
    next unless $properties->{$p}{readOnly};
    push @e, JSON::Validator::E("$path/$p", "Read-only.") if exists $data->{$p};
    $ro{$p} = 1;
  }

  local $schema->{required} = [grep { !$ro{$_} } @{$schema->{required} || []}];

  return @e, $self->SUPER::_validate_type_object($data, $path, $schema);
}

sub _build_formats {
  my $formats = shift->SUPER::_build_formats;

  $formats->{byte}   = \&_is_byte_string;
  $formats->{date}   = \&_is_date;
  $formats->{double} = \&Scalar::Util::looks_like_number;
  $formats->{float}  = \&Scalar::Util::looks_like_number;
  $formats->{int32}  = sub { _is_number($_[0], 'l'); };
  $formats->{int64}  = IV_SIZE >= 8 ? sub { _is_number($_[0], 'q'); } : sub {1};

  return $formats;
}

sub _is_byte_string { $_[0] =~ /^[A-Za-z0-9\+\/\=]+$/ }
sub _is_date        { $_[0] =~ /^(\d+)-(\d+)-(\d+)$/ }

sub _is_number {
  return unless $_[0] =~ /^-?\d+(\.\d+)?$/;
  return $_[0] eq unpack $_[1], pack $_[1], $_[0];
}

1;

=encoding utf8

=head1 NAME

Swagger2::SchemaValidator - Sub class of JSON::Validator

=head1 DESCRIPTION

This class is used to validate Swagger specification. It is a sub class of
L<JSON::Validator> and adds some extra functionality specific for L<Swagger2>.

=head1 ATTRIBUTES

L<Swagger2::SchemaValidator> inherits all attributes from L<JSON::Validator>.

=head2 formats

Swagger support the same formats as L<Swagger2::SchemaValidator>, but adds the
following to the set:

=over 4

=item * byte

A padded, base64-encoded string of bytes, encoded with a URL and filename safe
alphabet. Defined by RFC4648.

=item * date

An RFC3339 date in the format YYYY-MM-DD

=item * double

Cannot test double values with higher precision then what
the "number" type already provides.

=item * float

Will always be true if the input is a number, meaning there is no difference
between  L</float> and L</double>. Patches are welcome.

=item * int32

A signed 32 bit integer.

=item * int64

A signed 64 bit integer. Note: This check is only available if Perl is
compiled to use 64 bit integers.

=back

=head2 json_validator

  $obj = $self->json_validator;

Holds a L<JSON::Validator> object.

=head1 METHODS

L<Swagger2::SchemaValidator> inherits all attributes from L<JSON::Validator>.

=head2 coerce_by_collection_format

  $array = $self->coerce_by_collection_format(\%spec, $value);

Will take a C<%spec> containing "collectionFormat" and turn C<$value>
into an array.

=head2 validate_parameter

  @errors = $self->validate_parameter(\%spec, $name => $value);

Takes a L<parameter|http://swagger.io/specification/#parameterObject>
specification and validates C<$value> with parameter name C<$name>.

=head2 validate_input

This method will make sure "readOnly" is taken into account, when validating
data sent to your API.

=head1 FUNCTIONS

=head2 is_true

  $bool = Swagger2::SchemaValidator::is_true($value);

Will check if C<$value> looks like a boolean in any way. The code below is
close to the internal logic:

  return $_[0] if ref $_[0] and !Scalar::Util::blessed($_[0]);
  return 0 if !$_[0] or $_[0] =~ /^(n|false|off)/i;
  return 1;

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014-2015, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut
