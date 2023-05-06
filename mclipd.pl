use strict;
use HTTP::Daemon;
use HTTP::Status;
use HTTP::Status qw(:constants);
use Time::Piece;
use MIME::Types;
use HTML::Template;

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

my $data; # hash reference; holds all fields to describe data: content, filename, time, mimetype

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

	if($req->uri->path eq '/ui'){
		return HTTP::Response->new(200, undef, [], "kek!");
	}

	if($req->uri->path eq '/uptext'){
		return HTTP::Response->new(200, undef, [], "kek!");
	}

	if($req->uri->path eq '/upfile'){
		return HTTP::Response->new(200, undef, [], "kek!");
	}

	if($req->uri->path eq '/'){
		# GET /
		if($req->method eq 'GET'){
			return status_message_res(204) unless $data->{content}; # 204 empty response!
			if($req->uri->query eq "download"){
				return HTTP::Response->new(200, undef, ["content-disposition" => "attachment; filename=" . $data->{filename}, "content-type" => $data->{mimetype}] || generate_filename($data->{time}), $data->{content});
			}
			return return HTTP::Response->new(200, undef, ["content-disposition" => "attachment; filename=" . $data->{filename}, "content-type" => $data->{mimetype}] || generate_filename($data->{time}), $data->{content});
		}

		# POST /
		if($req->method eq "POST"){
			my $filename;
			if(my $header = $req->headers->header("content-disposition")){
				($filename) = $header =~ /\bfilename="([^"]+)"/; # extract filename
				$filename =~ s/[^a-zA-Z0-9_.-]/#/g; # remove funny characters and replace them with #
			}
			my $mime = undef;
			unless($mime = $req->header("content-type")){
				# check for plaintext
				# default is octet stream, generate filename.bin
			}
			my $time = time();
			$data = {
				content  => $req->content,
				filename => $filename || $time,
				time     => $time,
				mimetype => $mime
			};
			print $data->{filename}, "\n";
			return status_message_res(200);
		}

		# DELETE /
		if($req->method eq 'DELETE'){
			$data = undef;
			print "clipboard dumped!\n";
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

sub generate_filename {
	my $time = shift;
	return "file-$time";
}