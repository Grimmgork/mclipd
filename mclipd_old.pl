use strict;
use HTTP::Daemon;
use HTTP::Headers;
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
    send_response_chunked($c, $res->[0], $res->[1], $res->[2]);
    $c->close;
    undef($c);
}

sub send_response_chunked {
	my ($c, $code, $header, $chunks) = @_;
	my $h = HTTP::Headers->new(@$header);
	$h->header("transfer-encoding" => "chunked");
	if($code == HTTP_NO_CONTENT){
		$h->remove_header("content-type");
		$h->remove_header("transfer-encoding");
	}
	$c->send_status_line($code);
	foreach my $key ($h->header_field_names){
		print $key, " - ", $h->header($key), "\n";
		$c->send_header($key, $h->header($key));
	}

	print $c "\n";
	return if $code == HTTP_NO_CONTENT;

	my $i = 0;
	foreach(@$chunks){
		my $hex = sprintf("%X", length $_);
		print $c $hex, "\n";
		print $c $_, "\n";
		print "printing chunk $i\n";
		$i = $i + 1;
	}
	print $c "0\n\n";
	print "done!\n";
}

sub get_response {
	my ($req) = @_;
	print $req->method, " - ", $req->uri->path, "\n";

	if($req->uri->path eq '/ui'){
		return [200, [], ["kek!"]];
	}

	if($req->uri->path eq '/ui/text'){
		return [200, [], ["kek!"]];
	}

	if($req->uri->path eq '/ui/file'){
		return [200, [], ["kek!"]];
	}

	if($req->uri->path eq '/'){
		# GET /
		if($req->method eq 'GET'){
			return status_message_res(204) unless $data->{content}; # 204 empty response!
			return [200, ["Content-Disposition" => "attachment; filename=\"" . $data->{filename} . "\"", "content-type" => $data->{mimetype}], chop_content($data->{content}, 1024)];
		}

		# POST /
		if($req->method eq "POST"){
			my $filename;
			if(my $header = $req->headers->header("content-disposition")){
				($filename) = $header =~ /\bfilename=(.+)\b/; # extract filename
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

sub chop_content {
	my $content = shift;
	my $chunksize = shift || 2048;
	my @chunks;
	my $i = 0;
	while(my $chunk = substr $content, $i, $chunksize){
		push @chunks, $chunk;
		$i += length $chunk;
	}
	return \@chunks;
}

sub status_message_res {
	my $code = shift;
	my $message = status_message($code);
	return [$code, ["content-type" => "text/plain"], ["$code - $message"]];
}

sub generate_filename {
	my $time = shift;
	return "file-$time";
}