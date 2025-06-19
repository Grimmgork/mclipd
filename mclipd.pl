use HTTP::Server::PSGI;
use lib "lib";
use MetaClip;

use constant PORT => 5000;
use constant HOST => "127.0.0.1";

my $server = HTTP::Server::PSGI->new(
    host => HOST,
    port => PORT,
    timeout => 120
);

$server->run(\&MetaClip::app);