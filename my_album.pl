use strict;
use warnings;
use utf8;
use Encode;

use Imager;
use constant JPEG_QUALITY => 90;

use Getopt::Long qw/:config posix_default no_ignore_case bundling auto_help/;
use Pod::Usage qw/pod2usage/;

=head1 DESCRIPTION

フォトアルバムの静的HTML出力ツール

=head1 SYNOPSIS

    $ perl my_album.pl [--dry-run | -n]
    $ perl my_album.pl [--dry-run | -n] --config [config file]

    # config file
    {
        dir => '/Volumes/(Volume Name)/Foo/Bar',
        thumb => {
            dir => '~/Hoge/Huga',
            width => 1200
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

    my $thumb_dir = $config->{thumb}->{dir};
    if ( index($thumb_dir, '~') != -1 ) {
        $thumb_dir = glob( $thumb_dir ); # チルダを展開
    }

    if ( not -e $thumb_dir ) {
        print $thumb_dir, "\n";
        create_dir( $thumb_dir );
    }

    my %photo_dir = get_photo_dir( $config->{dir} );
    my $thumb_width = $config->{thumb}->{width};
    my @write_log = ();
    foreach my $dir_YYYY (sort(keys %photo_dir)) {
        my $dir_ary_ref = $photo_dir{$dir_YYYY};
        foreach my $dir_YYYYMMDD (@{$dir_ary_ref}) {
            #
            # ここで公開したくないフォルダ名をフィルタリング
            #
            next if ( $dir_YYYYMMDD =~ /Human/ );

            my $src_dir = join( '/', $config->{dir}, $dir_YYYY, $dir_YYYYMMDD );

            # todo:
            # フォルダの作成 & サムネイルの出力
            # フォルダの作成 & EXIFの出力
            my $dst_dir = join( '/', $thumb_dir, $dir_YYYY, $dir_YYYYMMDD );
            if ( not -e $dst_dir ) {
                create_dir( $dst_dir );
                print 'Created: ', $dst_dir, "\n";
            }
            else {
                #print $dst_dir, " is already exists.\n";
            }

            my @files = grep { /(\.jpeg|\.jpg)$/i; } get_files($src_dir);
            foreach my $file_name (@files) {
                my $src_path = $src_dir . '/' . $file_name;
                my $dst_path = $dst_dir . '/' . $file_name;

                my $image = Imager->new();
                $image->read( file => $src_path )
                    or die "Cannot read: ", $image->errstr;
                my $thumb = $image->scale(
                    xpixels => $thumb_width, ypixels => $thumb_width, qtype => 'mixing', type=>'min' );
                $thumb->write( file => $dst_path, jpegquality => JPEG_QUALITY )
                    or die $thumb->errstr;

                push @write_log, {
                    path => $dst_path,
                    width => $thumb->getwidth(),
                    height => $thumb->getheight(),
                };
            }

            foreach (@write_log) {
                print 'Created: ', $_->{path}, "\n";
            }

            exit(0);
            #
            #print $dir, ':', scalar(@files), "\n";
        }
    }
}

sub get_config {
    my $config_file = shift;
    
    if ( not -e $config_file ) {
        die "$config_file not found.";
    }

    return do $config_file;
}

sub get_photo_dir {
    my $root_dir = shift;
    my $rule = shift;

    if ( not $root_dir ) {
        die 'Check your config.'
    }

    if ( not -e $root_dir ) {
        die 'Photo directory not found.'
    }

#
#   こんな感じのフォルダ構造を想定
#   
#   $root_dir
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

    my @dir_YYYY = grep { /[\d]{4}/; } get_files($root_dir);

    my %photo_dir = ();
    foreach my $name (@dir_YYYY) {
        if ( $name =~ /[\d]{4}/ ) {
            my $sub_dir = join( '/', $root_dir, $name );
            my @dir_YYYYMMDD = grep { /$name[\d]{4}/; } get_files($sub_dir);
            $photo_dir{$name} = \@dir_YYYYMMDD;
        }
    }

    return %photo_dir;
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
                print $path, ' cannot create.', "\n";
                die $!;
            }
        }
    }
}

__END__