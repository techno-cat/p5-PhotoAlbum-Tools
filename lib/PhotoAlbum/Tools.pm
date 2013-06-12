package PhotoAlbum::Tools;
use 5.008005;
use strict;
use warnings;
use utf8;
use Encode;

use Imager;
use constant JPEG_QUALITY => 90;
use File::Spec;
use File::Path qw(make_path);

our $VERSION = "0.01";
our $dry_run = 0;

sub get_photo_dir {
    my $args = shift;

    my $photo_dir = ( exists $args->{dir} ) ? $args->{dir} : die '{dir} is required';
    my @ignore = ( exists $args->{ignore} ) ? @{$args->{ignore}} : ();
    my $rule = ( exists $args->{rule} ) ? $args->{rule} : '[\d]{8}'; # YYYYMMDD

    return grep {
        my $sub_dir = $_;
        if ( grep { $sub_dir =~ /$_/i; } @ignore ) {
            0; # 公開したくないフォルダ
        }
        else {
            ( -d File::Spec->catdir($photo_dir, $sub_dir) );
        }
    } _get_files($photo_dir, $rule);
}

# フォルダの作成 & サムネイルの出力
sub write_thumb {
    my $args = shift;

    my $photo_dir = ( exists $args->{dir} ) ? $args->{dir} : die '{dir} is required';
    my $rule = ( exists $args->{rule} ) ? $args->{rule} : '(\.jpeg|\.jpg)$'; # Default: JPEG file
    my @thumb_settings = ( exists $args->{thumb} ) ? @{$args->{thumb}} : die '{thumb} is required';

    foreach my $setting (@thumb_settings) {
        if ( not -e $setting->{dir} ) {
            if ( not $dry_run ) {
                _create_dir( $setting->{dir} );
            }
            print STDERR 'Created: ', $setting->{dir}, "\n";
        }
    }

    my @src_files = _get_files( $photo_dir, $rule );
    my $cnt = scalar(@src_files) * scalar(@thumb_settings);
    my @write_log = ();

    print STDERR sprintf( "%s (%2d/%2d)\r", $photo_dir, scalar(@write_log), $cnt );
    foreach my $file_name (@src_files) {
        my $src_path = File::Spec->catdir( $photo_dir, $file_name );

        my $image = Imager->new();
        $image->read( file => $src_path )
            or die "Cannot read: ", $image->errstr;

        foreach my $setting (@thumb_settings) {
            my $dst_path = File::Spec->catdir( $setting->{dir}, $file_name );

            if ( not $dry_run ) {
                my $w = $setting->{width};
                my $thumb = $image->scale(
                    xpixels => $w, ypixels => $w, qtype => 'mixing', type=>'min' );
                $thumb->write( file => $dst_path, jpegquality => JPEG_QUALITY )
                    or die $thumb->errstr;

                push @write_log, {
                    key    => $setting->{key},
                    path   => $dst_path,
                    width  => $thumb->getwidth(),
                    height => $thumb->getheight(),
                    jpegquality => JPEG_QUALITY
                };
            }
            else {
                push @write_log, {
                    key    => $setting->{key},
                    path   => $dst_path,
                    width  => 0,
                    height => 0,
                    jpegquality => JPEG_QUALITY
                };
            }

            print STDERR sprintf( "%s (%2d/%2d)\r", $photo_dir, scalar(@write_log), $cnt );
        }
    }
    print STDERR sprintf( "%s (%2d/%2d)\n", $photo_dir, scalar(@write_log), $cnt );

    return \@write_log;
}

# todo:
# フォルダの作成 & EXIFの出力
sub write_exif {
    my $self = shift;
}

sub _get_files {
    my $dir = shift;
    my $rule = shift;

    opendir( my $dh, $dir );

    # 日本語フォルダ名対策
    my @files = map { encode_utf8($_); } readdir( $dh );

    closedir( $dh );

    return grep { /$rule/i; } @files;
}

sub _create_dir {
    my $path = shift;

    my $err;
    make_path( $path, { error => \$err } );
    if ( @{$err} ) {
        _dump_error( $err );
        die 'Cannot create derectory.';
    }
}

sub _dump_error {
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

1;

=encoding utf-8

=head1 NAME

PhotoAlbum::Tools - It's new $module

=head1 SYNOPSIS

    use PhotoAlbum::Tools;

=head1 DESCRIPTION

PhotoAlbum::Tools supports your photo contents.

=head1 LICENSE

Copyright (C) techno-cat.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

techno-cat E<lt>techno(dot)cat(dot)miau(at)gmail(dot)comE<gt>

=cut
