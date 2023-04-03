use strict;
use HTTP::Daemon;
use HTTP::Status;
use HTTP::Status qw(:constants);
use Bytes::Random::Secure qw( random_string_from );
use feature 'state';
use Time::Piece;
use MIME::Types;

use constant CHUNKSIZE	=> 255;
use constant MIMETYPES	=> MIME::Types->new;

$SIG{PIPE} = 'IGNORE'; # prevent perl from quitting if trying to write to a closed socket ???

my $d = HTTP::Daemon->new(
	Host => "127.0.0.1",
	LocalPort => 5000,
	ReuseAddr => 1,
	Timeout => 1
) || die;

# print get_new_access_token(), "\n";
print localtime->strftime('%Y%m%d-%H%M%S');

print "starting metaclip server ...\n";
print "<URL:", $d->url, ">\n";

my $clipboard_data;
my $clipboard_name;
my $clipboard_time;

while(1) {
    my $c = $d->accept || next;
    my $req = $c->get_request;
    unless(defined $req){
		$c->close;
    		undef($c);
		next;
    }
    
    my $res;
    eval{ $res = get_response($req) };
    if($@){
		print "$@\n";
		$res = status_message_res(500);
    }
    $c->force_last_request;
    send_response_chunked($c, $res);
    $c->close;
    undef($c);
}

sub send_response_chunked {
	my ($c, $res) = @_;
	my $cd = $res->code;
	$res->header("transfer-encoding" => "chunked");
	if($res->code == HTTP_NO_CONTENT){
		$res->remove_header("content-type");
		$res->remove_header("transfer-encoding");
	}
	$c->send_status_line($res->code);
	my @fieldnames = $res->header_field_names;
	foreach my $key (@fieldnames){
		$c->send_header($key, $res->header($key));
	}

	print $c "\n";
	return if $res->code == HTTP_NO_CONTENT;

	my $i = 0;
	while(my $chunk = substr $res->content, $i, CHUNKSIZE){
		my $hex = sprintf("%X", length $chunk);
		print $c $hex, "\n";
		print $c $chunk, "\n";
		$i += length $chunk;
	}
	print $c "0\n\n";
}

sub get_response {
	my ($req) = @_;
	print $req->method, " - ", $req->uri->path, "\n";

	if($req->uri->path eq '/'){
		# GET /
		if($req->method eq 'GET'){
			if($clipboard_name){
				return status_message_res(204) unless $clipboard_data; # 204 empty response!
				return HTTP::Response->new(307, undef, ["location" => "/$clipboard_name"], undef);
			}
		}

		# DELETE /
		if($req->method eq 'DELETE'){
			$clipboard_data = undef;
			$clipboard_name = undef;
			$clipboard_time = undef;
			print "clipboard dumped!\n";
			return status_message_res(200);
		}

		# HEAD /
		if($req->method eq 'HEAD'){
			return status_message_res(204) unless $clipboard_data; # 204 empty response!
			return HTTP::Response->new(200, undef, ["location" => "/$clipboard_name", "last-modified" => "kek"], undef);
		}
	}

	# * /[file.txt]
	if(my ($filename) = $req->uri->path =~ m/^\/([a-z0-9_-~.]*)$/){
		# GET
		if($req->method eq 'GET'){
			return status_message_res(204) unless $clipboard_data; # 204 empty response!
			return status_message_res(404) unless ($filename eq $clipboard_name);
			return HTTP::Response->new(200, undef, ["last-modified" => "kek", "last-modified" => "kek"], $clipboard_data);
		}

		# POST 
		if($req->method eq "POST"){
			if($filename eq "") {
				# TODO: extract filename from content-disposition header
			}
			$clipboard_data = $req->content;
			$clipboard_name = $filename;
			$clipboard_time = time();
			return status_message_res(200);
		}
	}

	return status_message_res(404);
}

sub status_message_res {
	my $code = shift;
	my $message = status_message($code);
	return HTTP::Response->new($code, undef, ["content-type" => "text/plain"], "$code - $message");
}