use strict;
use HTTP::Daemon;
use HTTP::Status;
use Error ':try';

use constant CHUNKSIZE    => 255;

$SIG{PIPE} = 'IGNORE'; # prevent perl from quitting if trying to write to a closed socket ???

my $d = HTTP::Daemon->new(
	LocalPort => 9999,
	ReuseAddr => 1,
	Timeout => 3
) || die;
print "starting metaclip server ...\n";
print "<URL:", $d->url, ">\n";

my $clipboard_data = "";
my $clipboard_type;

while(1) {
    my $c = $d->accept || next;
    my $req = $c->get_request;
    unless(defined $req){
		$c->close;
    		undef($c);
		next;
    }

    my $res = process_req($req);
    $c->force_last_request;
    if ($res) {
		#$c->send_status_line($res->code);
		#$c->send_header("Transfer-Encoding", "Chunked");
		#print $c "\n";
		#open my $fh, '<:raw', 'test.mp4';
		#while(my $bytes_read = read $fh, my $bytes, 255){
		#	print $c "kek", "\n";
		#	print $c "kekekeke", "\n";
		#}
		$c->send_response($res);
    }
    else {
        $c->send_response(status_message_res(500));
    }
    print "B closing ...!\n";
    $c->close;
    undef($c);
}

sub process_req{
	my ($req) = @_;
	print$req->method, " - ", $req->uri->path, "\n";

	if($req->uri->path eq '/ping'){
		return HTTP::Response->new(200, undef, undef, "pong");
	}

	if($req->uri->path eq '/clip'){
		if($req->method eq 'GET'){
			return HTTP::Response->new(200, undef, ["Content-Type" => $clipboard_type], $clipboard_data);
		}
		if($req->method eq 'POST'){
			my $body = $req->content;
			my $type = $req->header("Content-Type");
			if(defined $body){
				$clipboard_data = $body;
				$clipboard_type = $type;
				print "clipped [$type]:\n";
   			}
			return status_message_res(200);
		}
	}
	return status_message_res(404);
}

sub status_message_res{
	my $code = shift;
	my $message = status_message($code);
	return HTTP::Response->new($code, undef, undef, "$code - $message");
}