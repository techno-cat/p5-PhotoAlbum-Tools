use strict;
use Test::More;

use FindBin qw($Bin);
use File::Spec;
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use Imager;

use_ok $_ for qw(
    PhotoAlbum::Tools
);

my $work_dir = tempdir( 'photo_album_XXXX', TMPDIR => 1, CLEANUP => 1 )
    or die 'Cannot create temp directory.';

my @dirs = File::Spec->splitdir( $work_dir );
my @sub_dirs = ( 'a', '1', '20130101_public', '20130102_private' );

foreach my $dir (@sub_dirs) {
    my @photo_dir = ( @dirs, $dir );
    make_path( File::Spec->catdir(@photo_dir) );

    my @test_paths = (
        File::Spec->catfile( @photo_dir, 'a.jpg'  ),
        File::Spec->catfile( @photo_dir, 'b.jpeg' ),
        File::Spec->catfile( @photo_dir, 'c.JPG'  )
    );

    foreach my $path (@test_paths) {
        my $image = Imager->new( xsize => 640, ysize => 480 );
        $image->write( file => $path )
            or die 'Cannot save $path: ', $image->errstr;
    }
}

{
    my @dir_ary = PhotoAlbum::Tools::get_photo_dir({
        dir  => $work_dir,
        rule => '^[a-z0-9]{1}$'
    });

    is scalar(@dir_ary), 2, 'select by rule.';
}

{
    my @dir_ary = PhotoAlbum::Tools::get_photo_dir({
        dir  => $work_dir,
        rule => '^[a-z0-9]{1}$',
        ignore => [ 'a' ]
    });

    is scalar(@dir_ary), 1, 'select by rule with ignore.';
    is $dir_ary[0], '1', 'selected directory name is "1".';
}

{
    my @dir_ary = PhotoAlbum::Tools::get_photo_dir({
        dir  => $work_dir,
        rule => '[0-9]{8}',
        ignore => [ 'private' ]
    });

    is scalar(@dir_ary), 1, 'select by rule with ignore..';
    is $dir_ary[0], '20130101_public', 'selected directory name is "20130101_public".';
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

done_testing;

