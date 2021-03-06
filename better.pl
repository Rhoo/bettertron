#!/usr/bin/perl -
use strict; 
use WWW::Mechanize;
use JSON -support_by_pp;
use JSON qw( decode_json );
use Data::Dumper;
use Bencode qw(bdecode);
use Config::IniFiles;
#use open IO  => ':locale';
use Encode;
use HTML::Entities;
use Crypt::SSLeay;

our $mech = WWW::Mechanize->new (
	timeout=>60,
);
our $username;
our $password;
our $flacdir;
our $transcodedir;
our $torrentdir;
our $passkey;
our $authkey;
our $debug;

sub chkCfg
{
	unless (-e $ENV{"HOME"} . "/.better")
	{
 		print "Your are running Bettertron for the first time!\n";
		print "Creating config file .better in home directory\n";
		print "Please read the README for how to fill out the config\n";
		open (MYFILE, ">> " . $ENV{"HOME"} . "/.better");
 		print MYFILE <<ENDHTML;
[user]
username=
password=

[dirs]
torrentdir=/blah/example/
flacdir=/look/another/
transcodedir=/fill/this/in/with/trailing/slashes/
[dev]
debug=0
ENDHTML
 		close (MYFILE);
		exit 0;
	}
	
	
}
sub getCfgValues
{
	#init config reading object
	my $cfg = Config::IniFiles->new( -file => $ENV{"HOME"} . "/.better" );

	#Get username and password from config file.
	$username = $cfg -> val('user', 'username');
	$password = $cfg -> val('user', 'password');

	#get all the directories we'll need
	$flacdir = $cfg -> val('dirs', 'flacdir');
	$transcodedir = $cfg -> val('dirs', 'transcodedir');
	$torrentdir = $cfg -> val('dirs', 'torrentdir');
	$debug = $cfg -> val('dev', 'debug');
	print "DEBUG:		Enabled\n" if $debug eq 1 or 2;
}


#this function will do our first login to what.cd. Get us persistence with cookies.
#Get our authkey for the API, passkey for torrent creation and so on.
sub initWeb
{
	if($debug eq 1 or 2)
	{ 
		print "DEBUG: 		Getting cookie\n"; 
	} 
	my $login_url = 'https://what.cd/ajax.php?action=index';
	$mech -> timeout;
	$mech -> cookie_jar(HTTP::Cookies->new());
	$mech -> get($login_url);
	$mech->submit_form(
	form_number => 1,
	fields =>
	{
	username=>$username,
	password=>$password
	}
	);
	my $login_info = decode_json($mech -> content());
	$passkey = $login_info->{'response'}{'passkey'};
	$authkey = $login_info->{'response'}{'authkey'};
	if($debug eq 1 or 2)
	 {
		 print "DEBUG: 		Got cookie!\n";
	 }
}


#get our better.php JSON object. In the future should be configurable.
#maybe even support the use of tags as per: 
#https://what.cd/forums.php?action=viewthread&threadid=66186&postid=3418797
sub getBetter
{
	#my $better_url = 'https://what.cd/ajax.php?action=better&method=single&authkey=' . $authkey;
	my $better_url = 'https://what.cd/ajax.php?action=better&method=snatch&filter=seeding&authkey=' . $authkey;
	if($debug eq "3") { print "DEBUG:		Getting better url\n$authkey\n"; }
	$mech -> get($better_url);
	my $better;
	print "DEBUG:		var Better content $better\n" if $debug eq 1 or 2;
	if($mech -> content() ne '')
	{ 
		$better = decode_json($mech -> content());
	}
	#if($debug eq "1") { print Dumper $better; }
	#if($debug eq "1") { print  Dumper $better_url; }

	return $better;
}

#better.php scraper until we have a JSON dump
sub getBetterScrape
{
	my $better_url = 'https://what.cd/better.php?method=snatch&filter=seeding';
	$mech -> get($better_url);
	#if($debug eq "1") { print "Matching"; }
	my @links = $mech->find_all_links ( 
                                     url_regex => qr{torrents\.php\?id=}
                                );
	return @links;

}

#This function takes a groupId and torrentId as an argument and goes out and gets the appropriate JSON.
#It finds the torrent which you have in the group and gets the torrent name for transcoding
#Also gets all the edition information so we can put the transcodes on the right torrent.
sub process
{
	my $groupId = $_[0];
	my $torrentId = $_[1];

        print "[----] Group ID: $groupId [----]\n";
        print "[----] Torrent ID: $torrentId [----]\n";


        my $group_url = 'https://what.cd/ajax.php?action=torrentgroup&id=' . $groupId . '&auth=' . $authkey;
        $mech -> get($group_url);
        my $group = decode_json($mech -> content());
	#print $mech -> content();

        my $remasterTitle = '';
	my $remasterYear = '';
	my $remasterRecordLabel = '';
	my $remasterCatalogueNumber = '';
	my $media = '';
	my $torrentName = '';
	my $torrentSize = '';
	my $torrentBytes = '';
        for my $torrents( @{$group->{'response'}{'torrents'}} )
        {
                if($torrents -> {'id'} eq $torrentId)
                {
                        $remasterTitle = $torrents -> {'remasterTitle'};
			$torrentName = decode_entities($torrents -> {'filePath'});
			$torrentSize = $torrents -> {'size'};
			$torrentBytes = $torrents -> {'size'};
			#if($debug eq "1") { print "DEBUG:		Torrent Bytes: $torrentSize\n"; }
			if ($torrentSize > 1048575) {
 				 $torrentSize = sprintf("%.2f MB",$torrentSize/1024/1024);#<-- Convert to MBs to two decimal places
			}
			elsif ($torrentSize > 1048576000) {
				$torrentSize = sprintf("%.2f GB",$torrentSize/1024/1024/1024);
			}
			#handle special chars for most file systems? works on mine at least
			$torrentName = encode('UTF-8', $torrentName);
			$remasterYear = $torrents -> {'remasterYear'};
			$remasterRecordLabel = $torrents -> {'remasterRecordLabel'};
			$remasterCatalogueNumber = $torrents -> {'remasterCatalogueNumber'};
                	$media = $torrents -> {'media'};
		}

        }
	print "[----] Remaster Title: $remasterTitle [---]\n";
	print "[----] Torrent Name: $torrentName [----]\n";
	print "[----] Finished Size: $torrentSize [----]\n"; 
	my %existing_encodes =
        (
        320 => '0',
        V0 => '0',
        V2 => '0',
        );
	#print Dumper $group;

        for my $torrents( @{$group->{'response'}{'torrents'}} )
        {
                if($torrents -> {'remasterTitle'} eq $remasterTitle && 
		$torrents->{'remasterYear'} == $remasterYear &&
		$torrents->{'remasterCatalogueNumber'} eq $remasterCatalogueNumber &&
		$torrents->{'remasterRecordLabel'} eq $remasterRecordLabel &&
		$torrents->{'media'} eq $media)
                {
                        if($torrents -> {'encoding'} eq '320')
                        {
                                $existing_encodes{'320'} = 1;
                        }
                        if($torrents -> {'encoding'} eq 'V0 (VBR)')
                        {
                                $existing_encodes{'V0'} = 1;
                        }
                        if($torrents -> {'encoding'} eq 'V2 (VBR)')
                        {
                                $existing_encodes{'V2'} = 1;
                        }
                }

        }
        my $command = "./converter.pl ";

        if($existing_encodes{'320'} == 0)
        {
                $command .= "--320 ";
        }
        if($existing_encodes{'V0'} == 0)
        {
                $command .= "--V0 ";
        }
        if($existing_encodes{'V2'} == 0)
        {
                $command .= "--V2 ";
        }

        $command .= "\"";
        $command .= $flacdir;
        $command .= $torrentName;
        $command .= "\"";

	my $fullDir = $flacdir . $torrentName;
	my $dirExists = undef;	
	my $lossyMaster = 0;
	my $calc = '';
	my $sizeDiff = '';
	my $percent = '';
	if(-d $fullDir)
	{
		$dirExists = 1;
	}
	else
	{
		$dirExists = 0;
	}
	if($dirExists == 1) {
	my $calc = '';
	$calc = `du -cbs "$fullDir" | tail -1 | awk {'print \$1'} 2>&1`;
	if($debug eq "2") { print "DEBUG:		Actual bytes: $calc\n"; }
	if($calc > $torrentBytes && $calc != 0) {
		 $sizeDiff = (($calc - $torrentBytes) / $torrentBytes) * 100;
		if($debug eq "2") { print "DEBUG:		torrentbytes -> realbytes\n"; }
	} elsif($torrentBytes > $calc && $calc != 0) 				{
		 $sizeDiff = (($torrentBytes - $calc) / $calc) * 100;
		if($debug eq "2") { print "DEUBG:		realbytes -> torrentbyes or else\n"; }
	}
	else
	{
			die("Critical: Unable to determine size of local directory");
	}
	print "DEBUG:		Raw difference: $sizeDiff\n" if $debug eq "1" or "2";

	
	if($sizeDiff >= 1)	
	{
		#downloading check - if file is larger than 1% different
		$percent = $sizeDiff > 0 ? 'larger' : 'smaller';
		printf "[!!!!] Expected size is %.2f%% $percent than disk size [!!!!]\n", abs $sizeDiff; 
		print "[!!!!] This file may be corrupt or unfinished - skipping. [!!!!]\n";
		$dirExists = 0;
	}
	else
	{
		print "[----] Everything seems to be OK. [----]\n";
	}
					}
	if($remasterTitle =~ m/pre-emphasis/i)
	{
		$lossyMaster = 1;
	}
	

        if($existing_encodes{'320'} == 1 && $existing_encodes{'V0'} == 1 && $existing_encodes{'V2'} == 1)
        {
                print "[++++] ERROR: Nothing to transcode. V2, V0, and 320 exist [++++]\n";
        }
	elsif($dirExists == 0)
	{
		print "[++++] Cannot find directory to transcode. Skipping to next [++++]\n";
	}
	elsif($lossyMaster == 1)
	{
		print "[++++] This FLAC appears to be a lossy master. Skipping to next entry [++++]\n";
	}
	else
        {
                print "[----] Running transcode [----]\n";
                print "DEBUG: 		OPTS: $command" if $debug eq "2";
                system($command);
		print "[----] Finished transcoding $torrentName [----]\n";
        }
        my $addformat_url = "https://what.cd/upload.php?groupid=" . $groupId;
        $mech -> get($addformat_url);

        #time to do the form post for uploading the torrent
        #if $remasterTitle is blank, we don't have to fill out edition info.
        while ( ((my $key, my $value) = each %existing_encodes) && $dirExists == 1 && $lossyMaster == 0)
	{

		my $bitrateDropdown = '';
		
		if ($existing_encodes{$key} == 0)
		{
			if($key eq 'V0' || $key eq 'V2')
			{
				$bitrateDropdown = $key . " (VBR)";	
			}
			else
			{
				$bitrateDropdown = $key;
			}
			#determine torrent file name & remove trailing [FLAC]s
			$torrentName =~ s/[\||\(|\[|\{| \|| \(| \[| \{]+[what.cd|FLAC]+[\}|\]|\)]//gi;
			my $torrentFile = $torrentName . " (" . $key . ").torrent";
			my $add_format_url = "https://what.cd/upload.php?groupid=" . $groupId;
			my $uploadFile = [ 
    			$torrentFile,        # The file we are uploading to upload.
    			$torrentFile,     # The filename we want to give the web server.
    			'Content-type' => 'text/plain' # Content type for bonus points.
];
				
			if($remasterYear == 0)
        		{
				print "\n+++++++++++++++++++++++++++++++++++++++++++++++++\n";
				print "[----] Starting Original Release upload: [----]\n";
				print "[----] Format: 		MP3 [----]\n";
				print "[----] Bitrate:		$bitrateDropdown [----]\n";
				print "[----] Media:		$media [----]\n";
				$mech -> get($add_format_url);
				
				$mech->form_id('upload_table');
				$mech->field('file_input', $uploadFile);
				$mech->select('format', 'MP3');
				$mech->select('bitrate', $bitrateDropdown);
				$mech->select('media', $media);
				
				$mech->submit();
				print "[----] Upload complete! [----]\n";
			}
			else
       			{
       				print "[----] Starting Edition Release upload: [----]\n";
				print "[----] Edition: 				$remasterTitle [----]\n";
				print "[----] Format: 							MP3 [----]\n";
                                print "[----] Bitrate: $bitrateDropdown [----]\n";
                                print "[----] Media: $media [----]\n";
				$mech -> get($add_format_url);
				
                                $mech->form_id('upload_table');
                                $mech->tick("remaster", 'on');
                                $mech->field('file_input', $uploadFile);
                                $mech->field('remaster_year', $remasterYear);
                                $mech->field('remaster_title', $remasterTitle);
                                $mech->field('remaster_record_label', $remasterRecordLabel);
                                $mech->field('remaster_catalogue_number', $remasterCatalogueNumber);
                                $mech->select('format', 'MP3');
                                $mech->select('bitrate', $bitrateDropdown);
                                $mech->select('media', $media);
                                
				
				$mech->submit();
				#print $mech->content();
			}
			#move torrent to watch/torrent folder
			my $torrentFileFinal = $torrentdir . $torrentFile;
			
			my $mvCmd = "\"" . $torrentFile . "\" \"" . $torrentFileFinal . "\"";
			`mv $mvCmd`;
		}
	}
}



#main

#argument checks
if (@ARGV > 1 )
{
	print "usage: ./better.pl OR ./better.pl  'https://what.cd/torrents.php?id=1000&torrentid=1000000'";
	exit;
}
if(@ARGV == 1 && $ARGV[0] !~ m/^https:\/\//)
{
	print "usage: argument does not appear to be a URL";
	exit;	
}
chkCfg();
getCfgValues();
print "[----] Configuration loaded, attempting to connect to What.CD [----]\n";
initWeb();
my $better = getBetter();

#processing only one torrent via argument else we process our better.php
if(@ARGV == 1)
{
	my $groupId = (split('&',(split('=', $ARGV[0]))[1]))[0];
	my $torrentId = (split('=', $ARGV[0]))[2];
	
	process($groupId, $torrentId);
}
elsif (@ARGV == 0 && defined $better)
{
	print "[----] Using JSON API for better.php source [----]\n";

	for my $href ( @{$better->{'response'}} )
	{
	
        	my $groupId = $href->{'groupId'};
		my $torrentId = $href->{'torrentId'};
		process($groupId, $torrentId);
	
		sleep 2;
		print "-------------------------------------------------------------------------------------\n";
	}	
}
else
{
	my @betterScrape = getBetterScrape();	
	#print Dumper(\@betterScrape);
	
	print "[----] JSON API did not return an answer. Fall back to scraping better.php directly [----]\n";

	foreach (@betterScrape)
	{
		my $scrapeUrl;
		foreach (@$_)
		{
			my $tmp;
			if(defined $_)
			{
				$tmp = $_;
				if($tmp =~ m/torrents\.php\?id=/)
                        	{
                                	$scrapeUrl = $_;
                                	#print "$scrapeUrl\n";
					my $groupId = (split('&',(split('=', $scrapeUrl))[1]))[0];
        				my $torrentId = (split('=', $scrapeUrl))[2];
					$torrentId = (split('#', $torrentId))[0];
					#print "$groupId $torrentId\n";
					process($groupId, $torrentId);
					print "------------------------------------------------------------------------\n";
                        	}
			}

		}
	}
}
