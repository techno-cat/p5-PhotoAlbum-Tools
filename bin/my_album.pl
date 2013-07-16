use strict;
use warnings;
use utf8;
use PhotoAlbum::Tools;
use Text::Xslate;
use FindBin qw($Bin);
use Encode;
use File::Spec;
use File::Path qw(make_path);
use Data::Dumper;

use Getopt::Long qw/:config posix_default no_ignore_case bundling auto_help/;
use Pod::Usage qw/pod2usage/;

=head1 DESCRIPTION

フォトアルバムの静的HTML出力ツール

=head1 SYNOPSIS

    # output thumbnail and log file.
    $ perl my_album.pl --update-thumb [--dry-run | -n] [--config] <config file>

    # output HTML from log files.
    $ perl my_album.pl [--dry-run | -n] [--config] <config file>

    # config file
    {
        dir     => '/Users/(User Name)/foo/bar',
        ignore  => [ 'private' ],   # not required (default: none)
        rule    => '[\d]{8}',       # not required (default: '[\d]{8}')
        thumb   => {
            large => {
                dir => '/Users/(User Name)/hoge/large',
                width => 1200
            },
            medium => {
                dir => '/Users/(User Name)/hoge/medium',
                width => 400
            },
            small => {
                dir => '/Users/(User Name)/hoge/small',
                width => 100
            }
        },
        log     => '/Users/(User Name)/hoge/log',
        pages   => {
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
    $Data::Dumper::Indent = 1;

    my %opt = ();
    GetOptions(
        \%opt,
        'config=s',
        'update-thumb',
        'dry-run|n'
    ) or pod2usage( 1 );

    my $config = ();
    if ( $opt{config} ) {
        #print 'config=', $opt{config}, "\n"
        $config = get_config( $opt{config} );
    }
    else {
        #print 'config from album.config', "\n"
        $config = get_config( 'album.config');
    }

    $config->{dry_run} = ( $opt{'dry-run'} or $opt{n} );
    if ( $config->{dry_run} ) {
        print 'this is dry-run.', "\n";
        $PhotoAlbum::Tools::dry_run = 1;
    }

    if ( $opt{'update-thumb'} ) {
        update_thumb( $config );
    }
    else {
        update_album( $config );
    }
}

sub update_thumb {
    my $config = shift;

    if ( not $config->{dir} ) {
        die 'Check your config.';
    }

    if ( not -e $config->{dir} ) {
        die 'Photo directory not found.';
    }

    if ( not $config->{'log'} ) {
        die 'Photo directory not found.';
    }

    if ( not -e $config->{'log'} ) {
        if ( not $config->{dry_run} ) {
            make_dir( $config->{'log'} );
        }
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
    foreach my $dir_YYYY (@dir_YYYY_ary) {
        my @dir_YYYYMMDD_ary = PhotoAlbum::Tools::get_photo_dir({
            dir  => File::Spec->catdir( $config->{dir}, $dir_YYYY ),
            rule => $dir_YYYY . '[\d]{4}',
            ignore => ( exists $config->{ignore} ) ? $config->{ignore} : []
        });

        my %logs = ();
        foreach my $dir_YYYYMMDD (@dir_YYYYMMDD_ary) {
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

        if ( 0 < scalar(keys %logs) ) {
            $write_logs{$dir_YYYY} = \%logs;
        }
    }

    if ( $config->{dry_run} ) {
        return;
    }

    # ログの書き出し
    foreach my $key (keys %write_logs) {
        my $path = File::Spec->catfile( $config->{'log'}, ($key . '.log') );
        open( my $fp, '>', $path ) or die "cannot open > $path: $!";
        print $fp encode_utf8( Dumper($write_logs{$key}) );
        close( $fp );
    }
}

sub update_album {
    my $config = shift;

    if ( not -e $config->{'log'} ) {
        die 'Log directory not found.';
    }

    # ログの読み込み
    my %logs = ();
    opendir( my $dh, $config->{'log'} );
    while ( readdir($dh) ) {
        if ( /([\d]{4})/ ) {
            my $key = $1;
            my $path = File::Spec->catfile( $config->{'log'}, $_ );
            $logs{$key} = do $path;
        }
    }
    closedir( $dh );

    my $album_source = create_album_source( $config->{pages}, \%logs );
    my $xslate = Text::Xslate->new(
        path => [ "$Bin/template" ]
    );

    # パス情報の確定
    my $page_index = $config->{pages}->{'index'};
    $page_index->{path} = File::Spec->catfile( $page_index->{dir}, $page_index->{file} );
#    print "$page_index->{path}\n";
    foreach my $page_YYYY (@{$album_source}) {
        $page_YYYY->{path} = File::Spec->catfile( $page_YYYY->{dir}, $page_YYYY->{file} );
#        print "$page_YYYY->{path}\n";
        foreach my $page (@{$page_YYYY->{children}}) {
            $page->{path} = File::Spec->catfile( $page->{dir}, $page->{file} );
#            print "$page->{path}\n";
        }
    }

    # HTMLの出力
    foreach my $page_YYYY (@{$album_source}) {
        # todo: YYYY.htmlの出力

        # YYYYMMDD.htmlの出力
        my @pages_YYYYMMDD = ();
        foreach my $page (@{$page_YYYY->{children}}) {
            $page->{content} = $xslate->render( $page->{template}, {
                paths => {
                    'index' => '',
                    parent  => '',
                    this    => './'
                },
                date => $page->{date},
                logs => $page->{logs}
            });
            push @pages_YYYYMMDD, $page;
        }

        print File::Spec->catfile($page_YYYY->{dir}, $page_YYYY->{file}), ': ', scalar(@pages_YYYYMMDD), "\n";
        if ( not $config->{dry_run} ) {
            write_pages( \@pages_YYYYMMDD );
        }
    }

    # todo: index.htmlの出力
}

sub create_album_source {
    my $pages_ref = shift;
    my $logs_ref = shift;

    my @pages_YYYY = ();
    foreach my $dir_YYYY (sort keys %{$logs_ref}) {

        my @pages = ();
        foreach my $dir_YYYYMMDD (sort keys %{$logs_ref->{$dir_YYYY}}) {
            my @tmp = ( $dir_YYYYMMDD =~ m/^([\d]{4})([\d]{2})([\d]{2})/ );
            my %date = ( YYYY => $tmp[0], MM => $tmp[1], DD => $tmp[2] );
            my $page = replaced_page( $pages_ref->{'YYYYMMDD'}, [
                { YYYY => $date{YYYY} },
                { MM   => $date{MM}   },
                { DD   => $date{DD}   }
            ]);

            # データ構造の変換
            my %photo_logs = ();
            foreach my $write_log (@{$logs_ref->{$dir_YYYY}->{$dir_YYYYMMDD}}) {
                my ($volume, $directories, $file) = File::Spec->splitpath( $write_log->{path} );
                if ( not (exists $photo_logs{$file}) ) {
                    $photo_logs{$file} = {};
                }

                $photo_logs{$file}->{$write_log->{key}} = $write_log;
            }

            my @sorted_logs = map { $photo_logs{$_}; } sort keys %photo_logs;

            $page->{logs} = \@sorted_logs;
            $page->{date} = \%date;
            push @pages, $page;
        }

        if ( @pages ) {
            my $page = replaced_page( $pages_ref->{'YYYY'}, [
                { 'YYYY' => $dir_YYYY }
            ]);

            $page->{children} = \@pages;
            push @pages_YYYY, $page;
        }
    }

    return \@pages_YYYY;
}

sub write_pages {
    my $pages_ref = shift;

    my $dir = $pages_ref->[0]->{dir};
    if ( not -e $dir ) {
        make_dir( $dir );
    }

    foreach my $page (@{$pages_ref}) {
        open( my $fp, '>', $page->{path} ) or die "cannot open > $page->{path}: $!";
        print $fp encode_utf8( $page->{content} );
        close( $fp );
    }
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

sub make_dir {
    my $err;
    make_path( $_[0], { error => \$err } );
    if ( @{$err} ) {
        dump_error( $err );
        die 'Cannot create derectory.';
    }
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