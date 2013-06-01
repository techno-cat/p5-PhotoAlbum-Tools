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
        dir => '/Users/(User Name)/foo/bar',
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

my $dry_run = 0;
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
        $dry_run = 1;
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

    my %photo_dir_tree = get_photo_dir_tree( $config->{dir} );
    foreach my $dir_YYYY (sort(keys %photo_dir_tree)) {
        my $dir_ary_ref = $photo_dir_tree{$dir_YYYY};
        foreach my $dir_YYYYMMDD (@{$dir_ary_ref}) {
            #
            # ここで公開したくないフォルダ名をフィルタリング
            #
            next if ( $dir_YYYYMMDD =~ /Human/ );

            # todo:
            # フォルダの作成 & サムネイルの出力
            # フォルダの作成 & EXIFの出力
            write_thumb( $config, $dir_YYYY, $dir_YYYYMMDD );
        }
    }
}

sub write_thumb {
    my $config = shift;
    my $dir_YYYY = shift;
    my $dir_YYYYMMDD = shift;

    my $src_dir = join( '/', $config->{dir}, $dir_YYYY, $dir_YYYYMMDD );
    my @src_files = grep { /(\.jpeg|\.jpg)$/i; } get_files($src_dir);

    my @dst_info = ();
    foreach my $thumb_config (@{$config->{thumb}}) {
        my $dst_dir = join( '/', $thumb_config->{dir}, $dir_YYYY, $dir_YYYYMMDD );
        if ( not -e $dst_dir ) {
            if ( not $dry_run ) {
                create_dir( $dst_dir );
            }
            print 'Created: ', $dst_dir, "\n";
        }
        else {
            #print $dst_dir, " is already exists.\n";
        }

        push @dst_info, {
            dir => $dst_dir,
            width => $thumb_config->{width}
        };
    }

    my $cnt = scalar(@src_files) * scalar(@dst_info);
    my @write_log = ();
    print STDERR sprintf( "%s (%2d/%2d)\r", $src_dir, scalar(@write_log), $cnt );
    foreach my $file_name (@src_files) {
        my $src_path = $src_dir . '/' . $file_name;

        my $image = Imager->new();
        $image->read( file => $src_path )
            or die "Cannot read: ", $image->errstr;

        foreach my $info (@dst_info) {
            my $dst_path = $info->{dir} . '/' . $file_name;

            my $w = $info->{width};
            my $thumb = $image->scale(
                xpixels => $w, ypixels => $w, qtype => 'mixing', type=>'min' );
            if ( not $dry_run ) {
                $thumb->write( file => $dst_path, jpegquality => JPEG_QUALITY )
                    or die $thumb->errstr;
            }

            push @write_log, {
                path => $dst_path,
                width => $thumb->getwidth(),
                height => $thumb->getheight(),
            };
        }
        print STDERR sprintf( "%s (%2d/%2d)\r", $src_dir, scalar(@write_log), $cnt );
    }
    printf( "%s (%2d/%2d)\n", $src_dir, scalar(@write_log), $cnt );
}

sub get_config {
    my $config_file = shift;
    
    if ( not -e $config_file ) {
        die "$config_file not found.";
    }

    return do $config_file;
}

sub get_photo_dir_tree {
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