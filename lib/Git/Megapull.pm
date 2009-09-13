use strict;
use warnings;
package Git::Megapull;
use base 'App::Cmd::Simple';
# ABSTRACT: clone or update all repositories found elsewhere

use autodie;
use String::RewritePrefix;

=head1 OVERVIEW

This library implements the C<git-megaclone> command, which will find a list of
remote repositories and clone them.  If they already exist, they will be
updated from their origins, instead.

=head1 USAGE

  git-megapull [-bcs] [long options...]
    -b --bare       produce bare clones
    -c --clonely    only clone things that do not exist; skip others
    -s --source     the source class (or a short form of it)

The source may be given as a full Perl class name prepended with an equals
sign, like C<=Git::Megapull::Source::Github> or as a short form, dropping the
standard prefix.  The previous source, for example, could be given as just
C<Github>.

=head1 TODO

  * prevent updates that are not fast forwards
  * do not assume "master" is the correct branch to merge

=head1 WRITING SOURCES

Right now, the API for how sources work is pretty lame and likely to change.
Basically, a source is a class that implements the C<repo_uris> method, which
returns a hashref like C<< { $repo_name => $repo_uri, ... } >>.  This is likely
to be changed slightly to instantiate sources with parameters and to allow
repos to have more attributes than a name and URI.

=cut

sub opt_spec {
  return (
    # [ 'private|p!', 'include private repositories'     ],
    [ 'bare|b!',    'produce bare clones'                              ],
    [ 'clonely|c',  'only clone things that do not exist; skip others' ],
    [ 'origin=o',   'name to use when creating or fetching; default: origin',
                    { default => 'origin' }                            ],
    [ 'source|s=s', "the source class (or a short form of it)",
                    { default => $ENV{GIT_MEGAPULL_SOURCE} }           ],
  );
}

sub execute {
  my ($self, $opt, $args) = @_;

  $self->usage_error("no source provided") unless $opt->{source};

  my $source = String::RewritePrefix->rewrite(
    { '' => 'Git::Megapull::Source::', '=' => '' },
    $opt->{source},
  );

  # XXX: validate $source as module name -- rjbs, 2009-09-13
  # XXX: validate $opt->{origin} -- rjbs, 2009-09-13

  eval "require $source; 1" or die;

  die "bad source: not a Git::Megapull::Source\n"
    unless eval { $source->isa('Git::Megapull::Source') };

  my $repos = $source->repo_uris;

  my %existing_dir  = map { $_ => 1 } grep { $_ !~ m{\A\.} and -d $_ } <*>;

  for my $name (sort { $a cmp $b } keys %$repos) {
    # next if $repo->{private} and not $opt->{private};

    my $name = $name;
    my $uri  = $repos->{ $name };

    if (-d $name and not $opt->{clonely}) {
      __do_cmd(
        "cd $name && "
        . "git fetch $opt->{origin} && "
        . "git merge $opt->{origin}/master 2>&1"
      );
    } else {
      my $bare = $opt->{bare} ? '--bare' : '';
      __do_cmd("git clone -o $opt->{origin} $bare $uri 2>&1");
    }

    delete $existing_dir{ $name };
  }

  for (keys %existing_dir) {
    warn "unknown directory found: $_\n";
  }
}

sub __do_cmd {
  my ($cmd) = @_;
  print "$cmd\n";
  print `$cmd`;
}

1;
