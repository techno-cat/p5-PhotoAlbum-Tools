package My::Album;
use strict;
use warnings;
use utf8;
use Encode;

use Imager;
use constant JPEG_QUALITY => 90;

our $dry_run = 0;

sub exec_my_album {
    my $config = shift;

    my @ignore = ( exists $config->{ignore} ) ? @{$config->{ignore}} : ();
    my @sub_dir_ary = grep {
        my $sub_dir = $_;
        #
        # ここで公開したくないフォルダをフィルタリング
        #
        my $tmp = grep { $sub_dir =~ /$_/i; } @ignore;
        ( $tmp == 0 );
    } get_photo_dir($config->{dir}, $config->{rule});

    foreach my $sub_dir (sort(@sub_dir_ary)) {
        # todo:
        # フォルダの作成 & サムネイルの出力
        # フォルダの作成 & EXIFの出力
        my @thumb_settings = map +{
            dir => join( '/', $_->{dir}, $sub_dir ),
            width => $_->{width}
        }, @{$config->{thumb}};

        foreach my $setting (@thumb_settings) {
            if ( not -e $setting->{dir} ) {
                if ( not $dry_run ) {
                    create_dir( $setting->{dir} );
                }
                print 'Created: ', $setting->{dir}, "\n";
            }
        }

        my $photo_dir = join( '/', $config->{dir}, $sub_dir );
        write_thumb( $photo_dir, \@thumb_settings );
    }
}

sub write_thumb {
    my $src_dir = shift;
    my $thumb_settings_ref = shift;

    my @src_files = grep { /(\.jpeg|\.jpg)$/i; } get_files($src_dir);
    my @thumb_settings = @{$thumb_settings_ref};

    my $cnt = scalar(@src_files) * scalar(@thumb_settings);
    my @write_log = ();
    print STDERR sprintf( "%s (%2d/%2d)\r", $src_dir, scalar(@write_log), $cnt );
    foreach my $file_name (@src_files) {
        my $src_path = $src_dir . '/' . $file_name;

        my $image = Imager->new();
        $image->read( file => $src_path )
            or die "Cannot read: ", $image->errstr;

        foreach my $setting (@thumb_settings) {
            my $dst_path = join( '/', $setting->{dir}, $file_name );

            if ( not $dry_run ) {
                my $w = $setting->{width};
                my $thumb = $image->scale(
                    xpixels => $w, ypixels => $w, qtype => 'mixing', type=>'min' );
                $thumb->write( file => $dst_path, jpegquality => JPEG_QUALITY )
                    or die $thumb->errstr;

                push @write_log, {
                    path   => $dst_path,
                    width  => $thumb->getwidth(),
                    height => $thumb->getheight(),
                };
            }
            else {
                push @write_log, {
                    path   => $dst_path,
                    width  => 0,
                    height => 0,
                };
            }
        }
        print STDERR sprintf( "%s (%2d/%2d)\r", $src_dir, scalar(@write_log), $cnt );
    }
    print STDERR sprintf( "%s (%2d/%2d)\n", $src_dir, scalar(@write_log), $cnt );
}

sub get_photo_dir {
    my $dir = shift;
    my $rule = shift;

    return grep { /$rule/i; } get_files($dir);
}

sub get_files {
    my $dir = shift;

    opendir( my $dh, $dir );

    # 日本語フォルダ名対策
    my @files = map { encode_utf8($_); } readdir( $dh );

    closedir( $dh );

    return @files;
}

# todo:
# Path::Classで置き換え
sub create_dir {
    my @wk = split( /\//, $_[0] );
    my $path = shift @wk;

    foreach my $dir (@wk) {
        $path .= ( '/' . $dir );
        if ( not -e $path ) {
            print $path, ' not found.', "\n";
            if ( not mkdir($path) ) {
                print STDERR $path, ' cannot create.', "\n";
                die $!;
            }
        }
    }
}

package main;
use strict;
use warnings;
use utf8;

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
        ignore => [ 'private' ], # 必須ではない（正規表現で指定）
        rule => '[\d]{8}', # サブフォルダがYYYYMMDDの場合
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
        $My::Album::dry_run = 1;
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

    foreach my $dir_YYYY (sort(My::Album::get_photo_dir($config->{dir}, '[\d]{4}'))) {
        my @ignore = ( exists $config->{ignore} ) ? @{$config->{ignore}} : ();
        my @thumb_settings = map +{
            dir => join( '/', $_->{dir}, $dir_YYYY ),
            width => $_->{width}
        }, @{$config->{thumb}};
        my $rule = $dir_YYYY . '[\d]{4}';

        My::Album::exec_my_album({
            dir    => join( '/', $config->{dir}, $dir_YYYY ),
            ignore => \@ignore,
            rule   => $config->{rule},
            thumb  => \@thumb_settings,
        });
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