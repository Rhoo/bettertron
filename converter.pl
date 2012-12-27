#!/usr/bin/perl

use strict;
use warnings;
use File::Basename qw/basename/;
use File::Find qw/find/;
use File::Path qw/mkpath/;
use File::Copy qw/copy/;
use Config::IniFiles;
use WWW::Mechanize;
use JSON -support_by_pp;
use JSON qw( decode_json );
use Data::Dumper;
use Cwd;
use threads;
#use open IO  => ':locale';
use Getopt::Long;
Getopt::Long::Configure("permute");

my ($verbose, $notorrent, $zeropad, $moveother, $output, $passkey, $torrent_dir);

##############################################################
# whatmp3 - Convert FLAC to mp3, create what.cd torrent.
# Created by shardz (logik.li)
# Based on: Flac to Mp3 Perl Converter by Somnorific
# Which was based on: Scripts by Falkano and Nick Sklaventitis
##############################################################

### VERSION 2.0

my $cfg = Config::IniFiles->new( -file => $ENV{"HOME"} . "/.better");

# Do you always want to move additional files (.jpg, .log, etc)? -- TD:	add this to config
$moveother = 1;

my $username = $cfg -> val('user', 'username');
my $password = $cfg -> val('user', 'password');
$output = $cfg -> val('dirs', 'transcodedir');
$torrent_dir = $cfg -> val('dirs', 'torrentdir');
my $debug = $cfg -> val('dev', 'debug');

my $pwd = getcwd();

# Do you want to zeropad tracknumber values? (1 => 01, 2 => 02 ...)
$zeropad = 1;

# Specify torrent passkey
my $login_url = 'http://what.cd/ajax.php?action=index';
my $mech = WWW::Mechanize->new();
$mech -> cookie_jar(HTTP::Cookies->new());
$mech -> get($login_url);
$mech->submit_form(
form_id => 'loginform',
fields =>
{
    username=>$username,
    password=>$password
}
);
my $login_info = decode_json($mech -> content());
$passkey = $login_info->{'response'}{'passkey'};
print "DEBUG:		PASSKEY: $passkey\n" if $debug eq "2";

# List of default encoding options, add to this list if you want more
my %lame_options = (
"320" => "-b 320 --ignore-tag-errors",
"V0"  => "-V 0 --vbr-new --ignore-tag-errors",
"V2"  => "-V 2 --vbr-new --ignore-tag-errors",
);

###
# End of configuration
###

my (@lame_options, @flac_dirs);

ARG: foreach my $arg (@ARGV) {
	foreach my $opt (keys %lame_options) {
		if ($arg =~ m/\Q$opt/i) {
			push(@lame_options, $opt);
			next ARG;
		}
	}
}

sub process {
	my $arg = shift @_;
	chop($arg) if $arg =~ m'/$';
	push(@flac_dirs, $arg);
}

sub msc
{
	system( @_ );
}

GetOptions('verbose' => \$verbose, 'notorrent' => \$notorrent, 'zeropad', => \$zeropad, 'moveother' => \$moveother, 'output=s' => \$output, 'passkey=s' => \$passkey, '<>' => \&process);

$output =~ s'/?$'/' if $output;	# Add a missing /

unless (@flac_dirs) {
	print "[!!!!] Need FLAC file parameter [!!!!]\n";
	exit 0;
}

# Store the lame options we actually want.

# die "Need FLAC file parameter\n" unless @flac_dirs;

foreach my $flac_dir (@flac_dirs) {
	my (@files, @dirs);
	find( sub { push(@files, $File::Find::name) if ($File::Find::name =~ m/\.flac$/i) }, $flac_dir);
	
	print "Using $flac_dir\n" if $verbose;
	
	foreach my $lame_option (@lame_options) {
		my $mp3_dir = $output . basename($flac_dir) . " ($lame_option)";
		$mp3_dir =~ s/[\||\(|\[|\{| \|| \(| \[| \{]+[what.cd|FLAC]+[\}|\]|\)]//gi; #removes trailing [FLAC] or (FLAC) from dir name
            mkpath($mp3_dir);
            
            print "\n[----] Encoding with $lame_option started... [----]\n" if $verbose;
            
            my @threads;
            
            foreach my $file (@files) {
                my (%tags, $mp3_filename);
                my $mp3_dir = $mp3_dir;
                if ($file =~ m!\Q$flac_dir\E/(.+)/.!) {
                    $mp3_dir .= '/' . $1;
                    mkpath($mp3_dir);
                }
                
                foreach my $tag (qw/TITLE ALBUM ARTIST TRACKNUMBER GENRE COMMENT DATE/) {
                    ($tags{$tag} = `metaflac --show-tag=$tag "$file" | awk -F = '{ printf(\$2) }'`) =~ s![:?/]!_!g;
                }
                
                $tags{'TRACKNUMBER'} =~ s/^(?!0|\d{2,})/0/ if $zeropad;	# 0-pad tracknumbers, if desired.
                
                if ($tags{'TRACKNUMBER'} and $tags{'TITLE'}) {
                    $mp3_filename = $mp3_dir . '/' . $tags{'TRACKNUMBER'} . " - " . $tags{'TITLE'} . ".mp3";
                } else {
                    $mp3_filename = $mp3_dir . '/' . basename($file) . ".mp3";
                }
                
                # Build the conversion script and do the actual conversion
                my $flac_command = "flac --totally-silent -dc \"$file\" | lame -S $lame_options{$lame_option} " .
				'--tt "' . $tags{'TITLE'} . '" ' .
				'--tl "' . $tags{'ALBUM'} . '" ' .
				'--ta "' . $tags{'ARTIST'} . '" ' .
				'--tn "' . $tags{'TRACKNUMBER'} . '" ' .
				'--tg "' . $tags{'GENRE'} . '" ' .
				'--ty "' . $tags{'DATE'} . '" ' .
				'--add-id3v2 - "' . $mp3_filename . '" >/dev/null';
				print "$flac_command\n" if $verbose;
				push @threads, threads->create('msc', $flac_command);
				#system($flac_command);
            }
            foreach (@threads)
            {
                $_->join();
            }
            
            
            print "\n[----] Encoding with $lame_option finished... [----]\n";
            
            if ($moveother) {
                print "Moving other files... " if $verbose;
                
                find( { wanted => sub {
                    if ($File::Find::name !~ m/\.flac$/i) {
                        if ($File::Find::name =~ m!\Q$flac_dir\E/(.+)/.!) {
                            mkpath($mp3_dir . '/' . $1);
                            copy($File::Find::name, $mp3_dir . '/' . $1);
                        } else {
                            copy($File::Find::name, $mp3_dir);
                        }
                    }
                }, no_chdir => 1 }, $flac_dir);
            }
            #find all our new files in the transcode dir
            
            my $fileString = `find '$mp3_dir' -type f -name '*'`;
            my @filesTranscode = split('\n', $fileString);
            
            
            #Remove all valid files from our list, leaving blacklisted ones we should delete
            @filesTranscode = grep {!/.accurip$/i} @filesTranscode;
            @filesTranscode = grep {!/.ac3$/i} @filesTranscode;
            @filesTranscode = grep {!/.cue$/i} @filesTranscode;
            @filesTranscode = grep {!/.dts$/i} @filesTranscode;
            @filesTranscode = grep {!/.ffp$/i} @filesTranscode;
            @filesTranscode = grep {!/.flac$/i} @filesTranscode;
            @filesTranscode = grep {!/.gif$/i} @filesTranscode;
            @filesTranscode = grep {!/.jpeg$/i} @filesTranscode;
            @filesTranscode = grep {!/.jpg$/i} @filesTranscode;
            @filesTranscode = grep {!/.log$/i} @filesTranscode;
            @filesTranscode = grep {!/.m3u$/i} @filesTranscode;
            @filesTranscode = grep {!/.m3u8$/i} @filesTranscode;
            @filesTranscode = grep {!/.m4a$/i} @filesTranscode;
            @filesTranscode = grep {!/.md5$/i} @filesTranscode;
            @filesTranscode = grep {!/.mp3$/i} @filesTranscode;
            @filesTranscode = grep {!/.mp4$/i} @filesTranscode;
            @filesTranscode = grep {!/.nfo$/i} @filesTranscode;
            @filesTranscode = grep {!/.pdf$/i} @filesTranscode;
            @filesTranscode = grep {!/.pls$/i} @filesTranscode;
            @filesTranscode = grep {!/.png$/i} @filesTranscode;
            @filesTranscode = grep {!/.sfv$/i} @filesTranscode;
            @filesTranscode = grep {!/.txt$/i} @filesTranscode;
            
            #actually delete them
            foreach my $tranFile (@filesTranscode)
            {
                unlink($tranFile);
            }
            
			
            if ($output and $passkey and not $notorrent) {
                print "\n[----] Creating torrent... [----]";
                my $torrent_create = 'mktorrent -p -a http://tracker.what.cd:34000/' . $passkey . '/announce -o "' . $pwd . '/' . basename($mp3_dir) . '.torrent" "' . $mp3_dir . '"';
                if($debug eq "1") { print "DEBUG:		'$torrent_create'\n"; }
                system($torrent_create);
            }
        }
        print "\nAll done with $flac_dir...\n" if $verbose;
    }
    
