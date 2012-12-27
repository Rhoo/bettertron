# New Bettertron, updated for ease of use with better error handling!

Bettertron is a tool that will scan your better.php. It will check a specified directory for your seeded FLACs and transcode them into the needed MP3 bitrates. It is edition aware and will transcode all the needed bitrates for the edition you are seeding, regardless of better.php.

### Installation & Dependencies:
***
If you are running ubuntu/debian, this should get all of them:

    $ apt-get install mktorrent flac lame

If you _don't_ have root access you can setup a local module installation with the following:

    $ wget -O- http://cpanmin.us | perl - -l ~/perl5 App::cpanminus local::lib
    $ eval `perl -I ~/perl5/lib/perl5 -Mlocal::lib`
    $ echo 'eval `perl -I ~/perl5/lib/perl5 -Mlocal::lib`' >> ~/.profile
    $ cpanm WWW::Mechanize, JSON, JSON::XS, Data::Dumper, Config::IniFiles, Bencode, Crypt::SSLeay

If you have root access run the following:

    $ sudo perl -MCPAN -e 'install WWW::Mechanize, JSON, JSON::XS, Data::Dumper, Config::IniFiles, Bencode, Crypt::SSLeay'

After that, simply run the better.pl script. It will generate a config file called ~/.better - You will need to edit this before use.
***
 * username = What.CD username
 * password = What.CD password
 * torrentdir = Torrent watch folder (new torrents go here)
 * flacdir = Torrent data folder (looks for torrents here)
 * transcodedir = Where new transcodes will go

### TODO:
 * Provide progress report
 * Remove useless info (torrent hashing etc)
 * Auto ignore torrents unsuitable for upload which have been marked by user (ie. .ignore_transcode file
 * Handle torrent upload errors more gracefully (had a couple rejected due to thumb.db restriction. 
 * Imagine 1982/original release/CD media will be a problem also)
 * Better error or unexpected condition handling.
