use strict;
use warnings;
use utf8;
use PhotoAlbum::Tools;
use Text::Xslate;
use FindBin qw($Bin);
use Encode;
use File::Spec;
use File::Path qw(make_path);

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
        thumb => {
            large => {
                dir => '/Users/(User Name)/hoge/large',
                width => 1200
            },
            midium => {
                dir => '/Users/(User Name)/hoge/midium',
                width => 400
            },
            small => {
                dir => '/Users/(User Name)/hoge/small',
                width => 100
            }
        },
        pages => {
            'index' => {
                dir  => '/Users/(User Name)/hoge/album',
                file => 'index.html',
                template => 'index.tx'
            },
            'YYYY' => {
                dir  => '/Users/(User Name)/hoge/album/YYYY',
                file => 'index.html',
                template => 'YYYY.tx'
            },
            'YYYYMMDD' => {
                dir  => '/Users/(User Name)/hoge/album/YYYY',
                file => 'YYYYMMDD.html',
                template => 'YYYYMMDD.tx'
            }
        }
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
            dir  => File::Spec->catdir( $config->{dir}, $dir_YYYY ),
            rule => $dir_YYYY . '[\d]{4}',
            ignore => ( exists $config->{ignore} ) ? $config->{ignore} : []
        });

        my %logs = ();
        foreach my $dir_YYYYMMDD (sort(@dir_YYYYMMDD_ary)) {
            my @thumb_settings = map {
                my $setting = $config->{thumb}->{$_};
                {
                    key   => $_,
                    dir   => File::Spec->catdir( $setting->{dir}, $dir_YYYY, $dir_YYYYMMDD ),
                    width => $setting->{width}
                };
            } keys %{$config->{thumb}};

            my $photo_dir = File::Spec->catdir( $config->{dir}, $dir_YYYY, $dir_YYYYMMDD );
            $logs{$dir_YYYYMMDD} = PhotoAlbum::Tools::write_thumb({
                dir => $photo_dir,
                thumb => \@thumb_settings
            });
        }

        $write_logs{$dir_YYYY} = \%logs;
    }

    write_photo_album({
        photo_dir => $config->{dir},
        thumb     => $config->{thumb},
        templ_dir => "$Bin/template",
        pages     => $config->{pages},
        logs => \%write_logs
    });
}

sub write_photo_album {
    my $args = shift;

    my $xslate = Text::Xslate->new(
        path => [ $args->{templ_dir} ],
    );

    foreach my $dir_YYYY (sort keys %{$args->{logs}}) {
        foreach my $dir_YYYYMMDD (sort keys %{$args->{logs}->{$dir_YYYY}}) {
            # YYYYMMDD.htmlの出力
            my $page = replaced_page( $args->{pages}->{'YYYYMMDD'}, [
                { 'YYYY' => $dir_YYYY },
                { 'YYYYMMDD' => $dir_YYYYMMDD }
            ]);

            if ( not -e $page->{dir} ) {
                my $err;
                make_path( $page->{dir}, { error => \$err } );
                if ( @{$err} ) {
                    dump_error( $err );
                    die 'Cannot create derectory.';
                }
            }

            # データ構造の変換
            my %photo_urls = ();
            foreach my $write_log (@{$args->{logs}->{$dir_YYYY}->{$dir_YYYYMMDD}}) {
                my ($volume, $directories, $file) = File::Spec->splitpath( $write_log->{path} );
                if ( not (exists $photo_urls{$file}) ) {
                    $photo_urls{$file} = {};
                }

                my $url = File::Spec->abs2rel( $write_log->{path}, $page->{dir} );
                $photo_urls{$file}->{$write_log->{key}} = $url;
            }

            my @tmp = ( $dir_YYYYMMDD =~ m/^([\d]{4})([\d]{2})([\d]{2})/ );
            my $content = $xslate->render( $page->{template}, {
                title => join('/', @tmp),
                urls  => \%photo_urls
            });

            my $path = File::Spec->catfile( $page->{dir}, $page->{file} );
            open( my $fp, '>', $path ) or die "cannot open > $path: $!";
            print $fp encode_utf8( $content );
            close( $fp );
        }

        # todo: YYYY.htmlの出力
    }

    # todo: index.htmlの出力
}

sub replaced_page {
    my %page = %{$_[0]};
    my $replace_settings_ref = $_[1];

    foreach my $setting (@{$replace_settings_ref}) {
        my ($from, $to) = %{$setting};
        $page{dir} =~ s/$from/$to/g;
        $page{file} =~ s/$from/$to/g;
    }

    return \%page;
}

sub get_config {
    my $config_file = shift;

    if ( not -e $config_file ) {
        die "$config_file not found.";
    }

    return do $config_file;
}

sub dump_error {
    my $err = shift;
    foreach my $diag (@{$err}) {
        my ($file, $message) = %{$diag};
        if ( $file eq '' ) {
            warn "general error: $message\n";
        }
        else {
            warn "problem unlinking $file: $message\n";
        }
    }
}

__END__