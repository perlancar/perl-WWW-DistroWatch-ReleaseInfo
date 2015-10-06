package WWW::DistroWatch::ReleaseInfo;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(
                       get_distro_releases_info
               );

our %SPEC;

$SPEC{get_distro_releases_info} = {
    v => 1.1,
    summary => "Get information about a distro's releases",
    description => <<'_',

This routine scrapes `http://distrowatch.com/table.php?distribution=<NAME>` and
returns a data structure like the following:

    [
        {
             release_name => '17.2 rafaela',
             release_date => '2015-06-30',
             eol_date => '2019-04',
             abiword_version => '--',
             alsa_lib_version => '1.0.27.2',
             perl_version => '5.22.0',
             python_version => '2.7.5',
             ...
        },
        ...
   ]

_
    args => {
        distribution => {
            schema => 'str*',
            summary => 'Name of distribution, e.g. "mint", "ubuntu", "debian"',
            req => 1,
            pos => 0,
        },
        file => {
            schema => 'str*',
            summary => "Instead of retrieving page from distrowatch.com, use this file's content",
            tags => ['category:testing'],
        },
    },
};
sub get_distro_releases_info {
    require Mojo::DOM;
    require Mojo::UserAgent;

    my %args = @_;

    my $ua   = Mojo::UserAgent->new;
    my $html;
    if ($args{file}) {
        {
            local $/;
            open my($fh), "<", $args{file}
                or return [500, "Can't read file '$args{file}': $!"];
            $html = <$fh>;
        }
    } else {
        my $url = "http://distrowatch.com/table.php?distribution=".
            $args{distribution};
        my $tx = $ua->get($url);
        unless ($tx->success) {
            my $err = $tx->error;
            return [500, "Can't retrieve URL '$url': ".
                        "$err->{code} - $err->{message}"];
        }
        $html = $tx->res->body;
    }

    my $dom  = Mojo::DOM->new($html);

    my $table = $dom->find("th.TablesInvert")->[0]->parent->parent;
    my @table;
    $table->find("tr")->each(
        sub {
            my $row = shift;
            push @table, $row->find("td,th")->map(
                sub { [$_->to_string,$_->text] })->to_array;
        }
    );
    #use DD; dd \@table;

    my %relcolnums; # key=distro name, val=column index
    for my $i (1..$#{$table[0]}-1) {
        $relcolnums{$table[0][$i][1]} = $i;
    }
    #use DD; dd \%relcolnums;

    my %fieldindexes = ( # key=field name, val=column index in result
        release_name => 0,
        release_date => 1,
        eol_date     => 2,
    );
    my $j = 3;

    my %fieldrownums; # key=field name, val=row index
    for my $i (1..$#table) {
        my ($chtml, $ctext) = @{ $table[$i][0] };
        if ($ctext =~ /release date/i) {
            $fieldrownums{release_date} = $i;
        } elsif ($ctext =~ /end of life/i) {
            $fieldrownums{eol_date} = $i;
        } elsif ($chtml =~ m!<a[^>]+>([^<]+)</a> \(.+\)!) {
            my $software = lc($1);
            $software =~ s/\W+/_/g;
            $fieldrownums{"${software}_version"} = $i;
            $fieldindexes{"${software}_version"} = $j++;
        }
    }
    #use DD; dd \%fieldrownums;

    my @rels;
    for my $relname (sort {$relcolnums{$b}<=>$relcolnums{$a}}
                         keys %relcolnums) {
        my $rel = {release_name => $relname};
        my $colnum = $relcolnums{$relname};
        for my $field (keys %fieldrownums) {
            my $rownum = $fieldrownums{$field};
            $rel->{$field} = $table[$rownum][$colnum][1];
        }
        push @rels, $rel;
    }

    [200, "OK", \@rels, {
        'table.fields'=>[sort{$fieldindexes{$a}<=>$fieldindexes{$b}} keys %fieldindexes],
    }];
}

1;
# ABSTRACT:

=cut
