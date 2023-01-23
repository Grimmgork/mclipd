use strict;
use HTTP::Daemon;
use HTTP::Status;

use constant CHUNKSIZE    => 255;

$SIG{PIPE} = 'IGNORE'; # prevent perl from quitting if trying to write to a closed socket ???

my $d = HTTP::Daemon->new(
	LocalPort => 9999,
	ReuseAddr => 1,
	Timeout => 3
) || die;

print "starting metaclip server ...\n";
print "<URL:", $d->url, ">\n";

my $clipboard_data;
my $clipboard_type;

while(1) {
    my $c = $d->accept || next;
    my $req = $c->get_request;
    unless(defined $req){
		$c->close;
    		undef($c);
		next;
    }

    my $res = get_response($req);
    $c->force_last_request;
    if ($res) {
		if(%{$res->headers}{"transfer-encoding"} eq "Chunked"){
			send_response_chunked($c, $res);
		}
		else{
			delete ${$res->headers}{"transfer-encoding"};
			$c->send_response($res);
		}
    }
    else{
		$c->send_response(status_message_res(500));
    }
    $c->close;
    undef($c);
}

sub send_response_chunked{
	my ($c, $res) = @_;

	$c->send_status_line($res->code);
	foreach my $key (keys %{$res->headers}){
		$c->send_header(%{$res->headers}{$key});
	}
	print $c "\n";
	my $i = 0;
	while(my $chunk = substr $res->content, $i, CHUNKSIZE){
		my $hex = sprintf("%X", length $chunk);
		print $c $hex, "\n";
		print $c $chunk, "\n";
		$i += length $chunk;
	}
	print $c "0\n\n";
}

sub get_response{
	my ($req) = @_;
	print $req->method, " - ", $req->uri->path, "\n";

	if($req->uri->path eq '/ping'){
		return HTTP::Response->new(200, undef, undef, "pong");
	}

	if($req->uri->path eq '/clip'){
		if($req->method eq 'GET'){
			unless($clipboard_data){
				return HTTP::Response->new(204, undef, undef, undef); # 204 empty response!
			}
			return HTTP::Response->new(200, undef, ["Content-Type" => $clipboard_type, "Transfer-Encoding" => "Chunked"], $clipboard_data);
		}

		if($req->method eq 'POST'){
			my $body = $req->content;
			my $type = $req->header("Content-Type");
			$body = undef if $body eq "";
			if(defined $body){
				$clipboard_data = $body;
				$clipboard_type = $type;
				print "clipped [$type]:\n";
   			}else{
				$clipboard_data = undef;
				$clipboard_type = undef;
				print "cleared clipboard!:\n";
			}
			return status_message_res(200);
		}

		if($req->method eq 'DELETE'){
			$clipboard_data = undef;
			$clipboard_type = undef;
			print "cleared clipboard!:\n";
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