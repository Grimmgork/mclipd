use strict;
use HTTP::Daemon;
use HTTP::Status;

my $d = HTTP::Daemon->new(
	LocalPort => 9999,
	ReuseAddr => 1
) || die;
print "starting metaclip server ...\n";
print "<URL:", $d->url, ">\n";

my $clipboard_data;
my $clipboard_type;

my $end;
while (not $end) {
    my $c = $d->accept;
    my $res = process_req($c->get_request);
    if ($res) {
	   $c->send_response($res);
    }
    else {
        $c->send_response(status_message_res(500));
    }
    $c->close;
    undef($c);
}

sub process_req{
	my ($req) = @_;

	if($req->uri->path eq '/clip'){
		if($req->method eq 'GET'){
			return HTTP::Response->new( 200, undef, ["Content-Type" => $clipboard_type], $clipboard_data);
		}
		if($req->method eq 'POST'){
			my $body = $req->content;
			my $type = $req->header("Content-Type");
			if(defined $body){
				$clipboard_data = $body;
				$clipboard_type = $type;
				print "clipped [$type]:\n";
   			}

			return HTTP::Response->new( 200, undef, undef, "done!");
		}
	}

	return status_message_res(404);
}

sub status_message_res{
	my $code = shift;
	my $message = status_message($code);
	return HTTP::Response->new($code, undef, undef, "$code - $message");
}