use strict;
use warnings;
use utf8;
use PhotoAlbum::Tools;

use Getopt::Long qw/:config posix_default no_ignore_case bundling auto_help/;
use Pod::Usage qw/pod2usage/;

=head1 DESCRIPTION

フォトアルバムの静的HTML出力ツール

=head1 SYNOPSIS

    $ perl my_album.pl [--dry-run | -n]
    $ perl my_album.pl [--dry-run | -n] --config [config file]

    # config file
    {
        dir => '/Users/(User Name)/foo/bar',
        ignore => [ 'private' ],    # not Required
        rule => '[\d]{8}',          # not Required
        thumb => [
            {   # Large
                dir => '/Users/(User Name)/hoge/large',
                width => 1200
            },
            {   # Midium
                dir => '/Users/(User Name)/hoge/midium',
                width => 400
            },
            {   # Small
                dir => '/Users/(User Name)/hoge/small',
                width => 100
            }
        ]
    };

=cut

main();

sub main {
    my %opt = ();

    GetOptions(
        \%opt,
        'config=s',
        'dry-run|n'
    ) or pod2usage( 1 );

    if ( $opt{'dry-run'} or $opt{n} ) {
        print 'this is dry-run.', "\n";
        $PhotoAlbum::Tools::dry_run = 1;
    }

    my $config = ();
    if ( $opt{config} ) {
        #print 'config=', $opt{config}, "\n"
        $config = get_config( $opt{config} );
    }
    else {
        #print 'config from album.config', "\n"
        $config = get_config( 'album.config');
    }

    if ( not $config->{dir} ) {
        die 'Check your config.';
    }

    if ( not -e $config->{dir} ) {
        die 'Photo directory not found.'
    }

#
#   こんな感じのフォルダ構造を想定
#   
#   $config->{dir}
#   ├── YYYY
#   │   ├── YYYYMMDD
#   │   ├── .
#   │   ├── .
#   │   ├── .
#   │   └── YYYYMMDD
#   ├── YYYY
#   │   ├── YYYYMMDD
#   │   ├── YYYYMMDD_hoge
#   │   ├── .
#   │   ├── .
#   │   ├── .
#   │   └── YYYYMMDD
#   .
#   .
#   .

    my @dir_YYYY_ary = PhotoAlbum::Tools::get_photo_dir({
        dir  => $config->{dir},
        rule => '[\d]{4}'
    });

    my %write_logs = ();
    foreach my $dir_YYYY (sort(@dir_YYYY_ary)) {
        my @dir_YYYYMMDD_ary = PhotoAlbum::Tools::get_photo_dir({
            dir  => join( '/', $config->{dir}, $dir_YYYY ),
            rule => $dir_YYYY . '[\d]{4}',
            ignore => ( exists $config->{ignore} ) ? $config->{ignore} : []
        });

        foreach my $dir_YYYYMMDD (sort(@dir_YYYYMMDD_ary)) {
            my @thumb_settings = map +{
                dir => join( '/', $_->{dir}, $dir_YYYY, $dir_YYYYMMDD ),
                width => $_->{width}
            }, @{$config->{thumb}};

            my $photo_dir = join( '/', $config->{dir}, $dir_YYYY, $dir_YYYYMMDD );
            my $write_log = PhotoAlbum::Tools::write_thumb({
                dir => $photo_dir,
                thumb => \@thumb_settings
            });

            $write_logs{$photo_dir} = $write_log;
        }
    }

    print 'write_logs count: ', scalar(keys %write_logs), "\n";
    foreach my $key (keys %write_logs) {
        my $cnt = scalar(@{$write_logs{$key}});
        $key =~ s/$config->{dir}//;
        printf( "%s => %3d\n", $key, $cnt );
    }
}

sub get_config {
    my $config_file = shift;

    if ( not -e $config_file ) {
        die "$config_file not found.";
    }

    return do $config_file;
}

__END__